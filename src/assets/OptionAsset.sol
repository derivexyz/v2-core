// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "openzeppelin/utils/math/SignedMath.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "lyra-utils/decimals/SignedDecimalMath.sol";
import "lyra-utils/encoding/OptionEncoding.sol";

import {ManagerWhitelist} from "./utils/ManagerWhitelist.sol";

import {IOptionAsset} from "../interfaces/IOptionAsset.sol";
import {ISubAccounts} from "../interfaces/ISubAccounts.sol";
import {IManager} from "../interfaces/IManager.sol";
import {ISettlementFeed} from "../interfaces/ISettlementFeed.sol";

import {PositionTracking} from "./utils/PositionTracking.sol";
import {GlobalSubIdOITracking} from "./utils/GlobalSubIdOITracking.sol";

/**
 * @title OptionAsset
 * @author Lyra
 * @notice Option asset that defines subIds, value and settlement
 */
contract OptionAsset is IOptionAsset, PositionTracking, GlobalSubIdOITracking, ManagerWhitelist {
  using SafeCast for uint;
  using SafeCast for int;
  using SignedDecimalMath for int;

  ///////////////////////
  //     Variables     //
  ///////////////////////

  /// @dev Contract to get spot prices which are locked in at settlement
  ISettlementFeed public settlementFeed;

  /// @dev Each account's total position: (sum of .abs() of all option positions)
  mapping(uint accountId => uint) public accountTotalPosition;

  ///////////////////////
  //    Constructor    //
  ///////////////////////

  constructor(ISubAccounts _subAccounts, address _settlementFeed) ManagerWhitelist(_subAccounts) {
    settlementFeed = ISettlementFeed(_settlementFeed);
  }

  ///////////////////////
  //  Admin Functions  //
  ///////////////////////

  /**
   * @notice Set the settlement feed contract
   */
  function setSettlementFeed(address _settlementFeed) external onlyOwner {
    settlementFeed = ISettlementFeed(_settlementFeed);
    emit SettlementFeedSet(_settlementFeed);
  }

  ///////////////////////
  //   Transfer Hook   //
  ///////////////////////

  function handleAdjustment(
    ISubAccounts.AssetAdjustment memory adjustment,
    uint tradeId,
    int preBalance,
    IManager manager,
    address /*caller*/
  ) external onlyAccounts returns (int finalBalance, bool needAllowance) {
    _checkManager(address(manager));

    // take snapshot of OI if this subId has not been traded in this tradeId
    if (!openInterestBeforeTrade[adjustment.subId][tradeId].initialized) {
      openInterestBeforeTrade[adjustment.subId][tradeId].initialized = true;
      openInterestBeforeTrade[adjustment.subId][tradeId].oi = openInterest[adjustment.subId].toUint240();
    }

    // take snapshot and update global OI (for OI fee charging if needed)
    _takeSubIdOISnapshotPreTrade(adjustment.subId, tradeId);
    _updateSubIdOI(adjustment.subId, preBalance, adjustment.amount);

    // take snapshot and update total position
    _takeTotalPositionSnapshotPreTrade(manager, tradeId);
    _updateTotalPositions(manager, preBalance, adjustment.amount);
    // update total position for account
    int postBalance = preBalance + adjustment.amount;
    accountTotalPosition[adjustment.acc] =
      accountTotalPosition[adjustment.acc] + SignedMath.abs(postBalance) - SignedMath.abs(preBalance);

    // always need allowance: cannot force send positive asset to other accounts
    return (postBalance, true);
  }

  ///////////////////////
  //  View Functions   //
  ///////////////////////

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
   * @notice Get settlement value of a specific option.
   * @dev Will return false if option not settled yet.
   * @param subId ID of option.
   * @param balance Amount of option held.
   * @return payout Amount the holder will receive or pay when position is settled
   * @return priceSettled Whether the settlement price of the option has been set.
   */
  function calcSettlementValue(uint subId, int balance) external view returns (int payout, bool priceSettled) {
    (uint expiry, uint strike, bool isCall) = OptionEncoding.fromSubId(subId.toUint96());

    (bool isSettled, uint settlementPrice) = _getSettlement(expiry);
    if (!isSettled) return (0, false);

    return (_getSettlementValue(strike, balance, settlementPrice, isCall), true);
  }

  function getSettlement(uint expiry) external view returns (bool isSettled, uint settlementPrice) {
    return _getSettlement(expiry);
  }

  function _getSettlement(uint expiry) internal view returns (bool isSettled, uint settlementPrice) {
    if (expiry > block.timestamp) {
      return (false, 0);
    }

    return settlementFeed.getSettlementPrice(uint64(expiry));
  }

  /**
   * @notice Get settlement value of a specific option position.
   */
  function _getSettlementValue(uint strikePrice, int balance, uint settlementPrice, bool isCall)
    internal
    pure
    returns (int)
  {
    int priceDiff = settlementPrice.toInt256() - strikePrice.toInt256();

    if (isCall && priceDiff > 0) {
      // ITM Call
      return priceDiff.multiplyDecimal(balance);
    } else if (!isCall && priceDiff < 0) {
      // ITM Put
      return -priceDiff.multiplyDecimal(balance);
    } else {
      // OTM
      return 0;
    }
  }
}
