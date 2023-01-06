// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/utils/math/SafeCast.sol";
import "synthetix/DecimalMath.sol";
import "synthetix/Owned.sol";
import "src/libraries/Black76.sol";
import "forge-std/console2.sol";

import "src/Accounts.sol";
import "src/interfaces/AccountStructs.sol";
import "src/interfaces/IAsset.sol";
import "src/libraries/IntLib.sol";

import "../assets/QuoteWrapper.sol";
import "../feeds/SettlementPricer.sol";
import "../feeds/PriceFeeds.sol";

// Adapter condenses all deposited positions into a single position per subId
contract OptionToken is IAsset, Owned {
  using IntLib for int;
  using SignedDecimalMath for int;
  using Black76 for Black76.Black76Inputs;
  using DecimalMath for uint;

  struct Listing {
    uint strikePrice;
    uint expiry;
    bool isCall;
  }

  Accounts account;
  PriceFeeds priceFeeds;
  SettlementPricer settlementPricer;

  uint feedId;
  uint96 nextId = 0;
  mapping(IManager => bool) riskModelAllowList;

  mapping(uint => uint) public totalLongs;
  mapping(uint => uint) public totalShorts;
  // need to write down ratio as totalOIs change atomically during transfers
  mapping(uint => uint) public ratios;
  mapping(uint => uint) public liquidationCount;

  mapping(uint96 => Listing) public subIdToListing;

  constructor(Accounts account_, PriceFeeds feeds_, SettlementPricer settlementPricer_, uint feedId_) Owned() {
    account = account_;
    priceFeeds = feeds_;
    settlementPricer = settlementPricer_;
    feedId = feedId_;

    priceFeeds.assignFeedToAsset(IAsset(address(this)), feedId);
  }

  //////////
  // Admin

  function setManagerAllowed(IManager riskModel, bool allowed) external onlyOwner {
    riskModelAllowList[riskModel] = allowed;
  }

  //////
  // Transfer

  // account.sol already forces amount from = amount to, but at settlement this isnt necessarily true.
  function handleAdjustment(
    AccountStructs.AssetAdjustment memory adjustment,
    int preBal,
    IManager riskModel,
    address caller
  ) external override returns (int finalBalance, bool needAllowance) {
    needAllowance = adjustment.amount < 0;
    Listing memory listing = subIdToListing[uint96(adjustment.subId)]; // TODO: can overflow
    int postBal = _getPostBalWithRatio(preBal, adjustment.amount, adjustment.subId);

    if (block.timestamp >= listing.expiry) {
      require(riskModelAllowList[IManager(caller)], "only RM settles");
      require(preBal != 0 && postBal == 0);
      return (postBal, needAllowance);
    }

    require(listing.expiry != 0 && riskModelAllowList[riskModel]);

    _updateOI(preBal, postBal, adjustment.subId);

    return (postBal, needAllowance);
  }

  ////
  // Liquidation

  function incrementLiquidations(uint subId) external {
    require(riskModelAllowList[IManager(msg.sender)], "only RM");
    liquidationCount[subId]++;
    // delay settlement for subid by n min
  }

  function decrementLiquidations(uint subId) external {
    require(riskModelAllowList[IManager(msg.sender)], "only RM");
    liquidationCount[subId]--;
    // delay settlement for subid by n min
  }

  /////
  // Option Value

  // currently hard-coded to optionToken but can have multiple assets if sharing the same logic
  function getValue(uint subId, int balance, uint spotPrice, uint iv) external view returns (int value) {
    Listing memory listing = subIdToListing[uint96(subId)];
    balance = _ratiodBalance(balance, subId);

    if (block.timestamp > listing.expiry) {
      SettlementPricer.SettlementDetails memory settlementDetails =
        settlementPricer.maybeGetSettlementDetails(feedId, listing.expiry);

      return _getSettlementValue(listing, balance, settlementDetails.price != 0 ? settlementDetails.price : spotPrice);
    }

    (uint callPrice, uint putPrice) = Black76.Black76Inputs({
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
    Listing memory listing = subIdToListing[uint96(subId)];
    SettlementPricer.SettlementDetails memory settlementDetails =
      settlementPricer.maybeGetSettlementDetails(feedId, listing.expiry);

    if (listing.expiry > block.timestamp || settlementDetails.price == 0) {
      return (0, false);
    }
    balance = _ratiodBalance(balance, subId);

    return (_getSettlementValue(listing, balance, settlementDetails.price), true);
  }

  function _getSettlementValue(Listing memory listing, int balance, uint spotPrice) internal pure returns (int value) {
    int PnL = (SafeCast.toInt256(spotPrice) - SafeCast.toInt256(listing.strikePrice));

    if (listing.isCall && PnL > 0) {
      // CALL ITM
      return PnL * balance / 1e18;
    } else if (!listing.isCall && PnL < 0) {
      // PUT ITM
      return -PnL * balance / 1e18;
    } else {
      // OTM
      return 0;
    }
  }

  //////
  // Views

  function _ratiodBalance(int balance, uint subId) internal view returns (int ratiodBalance) {
    if (ratios[subId] < 1e17) {
      // create some hardcoded limit to where asset freezes at certain levels of socialized losses
      revert("Socialized lossess too high");
    }
    // for socialised losses
    return _applyRatio(balance, subId);
  }

  function handleManagerChange(uint, IManager) external pure override {}

  function addListing(uint strike, uint expiry, bool isCall) external returns (uint subId) {
    Listing memory newListing = Listing({strikePrice: strike, expiry: expiry, isCall: isCall});
    subIdToListing[nextId] = newListing;
    ratios[nextId] = 1e18;
    ++nextId;
    return uint(nextId) - 1;
  }

  function socializeLoss(uint insolventAcc, uint subId, uint burnAmount) external {
    require(riskModelAllowList[IManager(msg.sender)], "only RM socializes losses");

    // only shorts can be socialized
    // open interest modified during handleAdjustment
    account.assetAdjustment(
      AccountStructs.AssetAdjustment({
        acc: insolventAcc,
        asset: IAsset(address(this)),
        subId: subId,
        amount: int(burnAmount),
        assetData: bytes32(0)
      }),
      true,
      ""
    );

    ratios[subId] = DecimalMath.UNIT * totalShorts[subId] / totalLongs[subId];
  }

  function _getPostBalWithRatio(int preBal, int amount, uint subId) internal view returns (int postBal) {
    bool crossesZero;
    if (preBal < 0) {
      crossesZero = preBal.abs() < amount.abs() && amount > 0 ? true : false;

      if (crossesZero) {
        return _applyInverseRatio((amount + preBal), subId);
      } else {
        return preBal + amount;
      }
    } else {
      crossesZero = preBal.abs() < (_applyInverseRatio(amount, subId)).abs() && amount < 0 ? true : false;

      if (crossesZero) {
        return amount + _applyRatio(preBal, subId);
      } else {
        return preBal + _applyInverseRatio(amount, subId);
      }
    }
  }

  function _applyRatio(int amount, uint subId) internal view returns (int) {
    return int(ratios[subId]) * amount / SignedDecimalMath.UNIT;
  }

  function _applyInverseRatio(int amount, uint subId) internal view returns (int) {
    int inverseRatio = SignedDecimalMath.UNIT.divideDecimal(int(ratios[subId]));
    return (inverseRatio * amount / SignedDecimalMath.UNIT);
  }

  function _updateOI(int preBal, int postBal, uint subId) internal {
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

  // add in a function prefixed with test here to prevent coverage from picking it up.
  function test() public {}
}
