pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import "synthetix/DecimalMath.sol";
import "synthetix/Owned.sol";
import "util/BlackScholesV2.sol";
import "forge-std/console2.sol";

import "src/Account.sol";
import "src/interfaces/IAbstractAsset.sol";

import "../assets/QuoteWrapper.sol";
import "../feeds/SettlementPricer.sol";
import "../feeds/PriceFeeds.sol";

// Adapter condenses all deposited positions into a single position per subId
contract OptionToken is IAbstractAsset, Owned {
  using SignedDecimalMath for int;
  using BlackScholesV2 for BlackScholesV2.BlackScholesInputs;
  using DecimalMath for uint;

  struct Listing {
    uint strikePrice;
    uint expiry;
    bool isCall;
  }

  Account account;
  PriceFeeds priceFeeds;
  SettlementPricer settlementPricer;

  uint feedId;
  uint nextId = 0;
  mapping(IAbstractManager => bool) riskModelAllowList;

  mapping(uint => uint) totalLongs;
  mapping(uint => uint) totalShorts;

  mapping(uint => uint) liquidationCount;

  constructor(
    Account account_, PriceFeeds feeds_, SettlementPricer settlementPricer_, uint feedId_
  ) Owned() {
    account = account_;
    priceFeeds = feeds_;
    settlementPricer = settlementPricer_;
    feedId = feedId_;

    priceFeeds.assignFeedToAsset(IAbstractAsset(address(this)), feedId);
  }

  //////////
  // Admin

  function setRiskModelAllowed(IAbstractManager riskModel, bool allowed) external onlyOwner {
    riskModelAllowList[riskModel] = allowed;
  }

  //////
  // Transfer

  // account.sol already forces amount from = amount to, but at settlement this isnt necessarily true.
  function handleAdjustment(uint, int preBal, int postBal, uint subId, IAbstractManager riskModel, address caller)
    external
    override
  {
    Listing memory listing = subIdToListing(subId);

    if (block.timestamp >= listing.expiry) {
      require(riskModelAllowList[IAbstractManager(caller)], "only RM settles");
      require(preBal != 0 && postBal == 0);
      return;
    }

    require(listing.expiry != 0 && riskModelAllowList[riskModel]);

    if (preBal < 0) {
      totalShorts[subId] -= uint(-preBal);
    } else {
      totalLongs[subId] -= uint(preBal);
    }

    if (postBal < 0) {
      totalShorts[subId] += uint(-postBal);
    } else {
      totalLongs[subId] += uint(postBal);
    }
  }

  ////
  // Liquidation

  function incrementLiquidations(uint subId) external {
    require(riskModelAllowList[IAbstractManager(msg.sender)], "only RM");
    liquidationCount[subId]++;
    // delay settlement for subid by n min
  }

  function decrementLiquidations(uint subId) external {
    require(riskModelAllowList[IAbstractManager(msg.sender)], "only RM");
    liquidationCount[subId]--;
    // delay settlement for subid by n min
  }

  /////
  // Option Value

  // currently hard-coded to optionToken but can have multiple assets if sharing the same logic
  function getValue(uint subId, int balance, uint spotPrice, uint iv) external view returns (int value) {
    Listing memory listing = subIdToListing(subId);
    balance = _ratiodBalance(subId, balance);

    if (block.timestamp > listing.expiry) {
      SettlementPricer.SettlementDetails memory settlementDetails = settlementPricer.maybeGetSettlementDetails(feedId, listing.expiry);

      return _getSettlementValue(listing, balance, settlementDetails.price != 0 ? settlementDetails.price : spotPrice);
    }

    (uint callPrice, uint putPrice) = BlackScholesV2.BlackScholesInputs({
    timeToExpirySec: listing.expiry,
    volatilityDecimal: iv,
    spotDecimal: spotPrice,
    strikePriceDecimal: listing.strikePrice,
    rateDecimal: 5e16
    }).prices();

    value = (listing.isCall) ? balance.multiplyDecimal(int(callPrice)) : balance.multiplyDecimal(int(putPrice));
    return value;
  }

  /////
  // Settlement

  function calculateSettlement(uint subId, int balance) external view returns (int PnL, bool settled) {
    Listing memory listing = subIdToListing(subId);
    SettlementPricer.SettlementDetails memory settlementDetails = settlementPricer.maybeGetSettlementDetails(feedId, listing.expiry);

    if (listing.expiry < block.timestamp || settlementDetails.price == 0) {
      return (0, false);
    }
    balance = _ratiodBalance(subId, balance);

    return (_getSettlementValue(listing, balance, settlementDetails.price), true);
  }

  function _getSettlementValue(Listing memory listing, int balance, uint spotPrice) internal pure returns (int value) {
    int PnL = (SafeCast.toInt256(spotPrice) - SafeCast.toInt256(listing.strikePrice));

    if (listing.isCall && PnL > 0) {
      // CALL ITM
      return PnL * balance;
    } else if (!listing.isCall && PnL < 0) {
      // PUT ITM
      return -PnL * balance;
    } else {
      // OTM
      return 0;
    }
  }

  //////
  // Views

  /**
   * subId encodes strike, expiry and isCall
   * bit 0 => isCall
   * bits 64-128 => expiry
   * bits 128-256 => strikePrice
   */

  // TODO: need to remove subId encoding to make work with uint96 subId

  function subIdToListing(uint subId) public pure returns (Listing memory) {
    return Listing({strikePrice: uint(uint128(subId)), expiry: uint(uint(subId >> 128)), isCall: subId >> 255 == 1});
  }

  function listingToSubId(Listing memory listing) public pure returns (uint subId) {
    require(listing.strikePrice < 2 ** 128);
    require(listing.expiry < 2 ** 64);
    subId = listing.isCall ? uint(1 << 255) : 0;
    return subId + (listing.expiry << 128) + (listing.strikePrice);
  }

  function listingParamsToSubId(uint strikePrice, uint expiry, bool isCall) public pure returns (uint subId) {
    return listingToSubId(Listing({strikePrice: strikePrice, expiry: expiry, isCall: isCall}));
  }

  function _ratiodBalance(uint subId, int balance) internal view returns (int ratiodBalance) {
    if (totalLongs[subId] == 0) {
      return balance;
    }
    // for socialised losses
    return int(DecimalMath.UNIT * totalShorts[subId] / totalLongs[subId]) * balance / SignedDecimalMath.UNIT;
  }

  function handleManagerChange(uint, IAbstractManager, IAbstractManager) external pure override {}
}
