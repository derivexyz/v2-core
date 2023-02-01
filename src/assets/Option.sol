// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/utils/math/SafeCast.sol";

import "src/interfaces/IOption.sol";
import "src/interfaces/ISpotFeeds.sol";
import "src/interfaces/IAccounts.sol";
import "src/interfaces/ISettlementFeed.sol";

import "src/libraries/Owned.sol";
import "src/libraries/OptionEncoding.sol";
import "src/libraries/SignedDecimalMath.sol";

/**
 * @title Option
 * @author Lyra
 * @notice Option asset that defines subIds, value and settlement
 */
contract Option is IOption, ISettlementFeed, Owned {
  using SafeCast for uint;
  using SafeCast for int;
  using SignedDecimalMath for int;

  ///////////////
  // Variables //
  ///////////////

  /// @dev Adderss of the Account module
  IAccounts immutable accounts;

  /// @dev spotFeeds that determine settlement prices
  ISpotFeeds public spotFeeds;

  ///@dev SubId => tradeId => open interest snapshot
  mapping(uint => mapping(uint => OISnapshot)) public openInterestBeforeTrade;

  ///@dev OI for a subId. OI is the sum of all positive balance
  mapping(uint => uint) public openInterest;

  ///@dev SubId => Settlement price
  mapping(uint => uint) public settlementPrices;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(IAccounts _accounts, address _spotFeeds) {
    accounts = _accounts;
    spotFeeds = ISpotFeeds(_spotFeeds);
  }

  ///////////////
  // Transfers //
  ///////////////

  function handleAdjustment(
    AccountStructs.AssetAdjustment memory adjustment,
    uint tradeId,
    int preBalance,
    IManager, /*manager*/
    address /*caller*/
  ) external onlyAccount returns (int finalBalance, bool needAllowance) {
    // todo: check whitelist

    // todo: make sure valid subId

    // take snapshot of OI if this subId has not been traded in this tradeId
    if (!openInterestBeforeTrade[adjustment.subId][tradeId].initialized) {
      openInterestBeforeTrade[adjustment.subId][tradeId].initialized = true;
      openInterestBeforeTrade[adjustment.subId][tradeId].oi = openInterest[adjustment.subId].toUint240();
    }

    // update the OI based on pre balance and change amount
    _updateOI(adjustment.subId, preBalance, adjustment.amount);

    return (preBalance + adjustment.amount, adjustment.amount < 0);
  }

  function handleManagerChange(uint accountId, IManager newManager) external onlyAccount {
    // todo: check whitelist
  }

  ////////////////
  // Settlement //
  ////////////////

  /**
   * @notice Locks-in price at which option settles.
   * @dev Settlement handled by option to simplify multiple managers settling same option
   * @param subId ID of option
   */
  function setSettlementPrice(uint subId) external {
    // todo: integrate with settlementFeeds
    if (settlementPrices[subId] != 0) revert SettlementPriceAlreadySet(subId, settlementPrices[subId]);
    (uint expiry,,) = OptionEncoding.fromSubId(SafeCast.toUint96(subId));
    if (expiry > block.timestamp) revert NotExpired(expiry, block.timestamp);

    uint price = spotFeeds.getSpot(1);

    settlementPrices[subId] = price;
    emit SettlementPriceSet(subId, 0);
  }

  //////////
  // View //
  //////////

  /**
   * @notice Decode subId into expiry, strike and whether option is call or put
   * @param subId ID of option.
   */
  function getOptionDetails(uint96 subId) external pure returns (uint expiry, uint strike, bool isCall) {
    return OptionEncoding.fromSubId(subId);
  }

  /**
   * @notice Encode subId into expiry, strike and whether option is call or put
   * @param expiry Expiration of option in epoch time.
   * @param strike Strike price of option.
   * @param isCall Whether option is a call or put
   */
  function getSubId(uint expiry, uint strike, bool isCall) external pure returns (uint96 subId) {
    return OptionEncoding.toSubId(expiry, strike, isCall);
  }

  /**
   * @notice Get settlement value of a specific option. Will return false if option not settled yet.
   * @param subId ID of option.
   * @param balance Amount of option held.
   * @return payout Amount the holder will receive or pay when position is settled
   * @return priceSettled Whether the settlement price of the option has been set.
   */
  function calcSettlementValue(uint subId, int balance) external view returns (int payout, bool priceSettled) {
    // todo: basic pnl
    (uint expiry, uint strike, bool isCall) = OptionEncoding.fromSubId(SafeCast.toUint96(subId));
    uint settlementPrice = settlementPrices[subId];

    // Return false if option cannot be settled yet or price settlement price has not been set
    if (expiry > block.timestamp || settlementPrice == 0) {
      return (0, false);
    } 

    return (_getSettlementValue(strike, balance, settlementPrice, isCall), true);
  }

  //////////////
  // Internal //
  //////////////

  /**
   * @dev update global OI for an subId, base on adjustment of a single account
   * @param preBalance Account balance before an adjustment
   * @param change Change of balance
   */
  function _updateOI(uint subId, int preBalance, int change) internal {
    int postBalance = preBalance + change;
    if (preBalance >= 0) {
      if (postBalance >= 0) {
        // OI can be increased or decrease. result must be postive
        openInterest[subId] = (openInterest[subId].toInt256() + change).toUint256();
      } else {
        // OI must be decreased, by amount of prebalance
        openInterest[subId] -= uint(preBalance);
      }
    } else {
      if (postBalance > 0) {
        // balance went from negative to positive: total positive increased by ending amount
        openInterest[subId] += uint(postBalance);
      }
      // if both pre and post balances are negative, this trade doesn't affect total positive
    }
  }

  function _getSettlementValue(uint strikePrice, int balance, uint settlementPrice, bool isCall)
    internal
    pure
    returns (int)
  {
    int payout = (settlementPrice - strikePrice).toInt256();

    if (isCall && payout > 0) {
      // ITM Call
      return payout.multiplyDecimal(balance);
    } else if (!isCall && payout < 0) {
      // ITM Put
      return -payout.multiplyDecimal(balance);
    } else {
      // OTM
      return 0;
    }
  }

  /////////////////
  //  Modifiers  //
  /////////////////

  modifier onlyAccount() {
    if (msg.sender != address(accounts)) revert OA_NotAccounts();
    _;
  }
}
