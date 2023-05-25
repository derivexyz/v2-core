// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "openzeppelin/utils/math/SignedMath.sol";
import "openzeppelin/access/Ownable2Step.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "lyra-utils/math/IntLib.sol";

import {IOITracking} from "src/interfaces/IOITracking.sol";
import {IManager} from "src/interfaces/IManager.sol";

/**
 * @title OITracking
 * @author Lyra
 * @notice contract helping assets to track OI and total supply, useful for charging fees, caps.. etc
 */
contract OITracking is Ownable2Step, IOITracking {
  using SafeCast for uint;
  using SafeCast for int;
  using IntLib for int;

  ///@dev SubId => tradeId => open interest snapshot
  mapping(uint subId => mapping(uint tradeId => OISnapshot)) public openInterestBeforeTrade;

  ///@dev Open interest for a subId. OI is the sum of all positive balance
  mapping(uint subId => uint) public openInterest;

  ///@dev Cap on each manager's max position sum. This aggregates .abs() of all opened position
  mapping(IManager manager => uint) public totalPositionCap;

  ///@dev Each manager's max position sum. This aggregates .abs() of all opened position
  mapping(IManager manager => uint) public totalPosition;

  ///////////////////////
  //    Admin-Only     //
  ///////////////////////

  function setTotalPositionCap(IManager manager, uint cap) external onlyOwner {
    totalPositionCap[manager] = cap;

    emit TotalPositionCapSet(address(manager), cap);
  }

  //////////////
  // Internal //
  //////////////

  function _migrateTotalPositionAndCheckCaps(uint pos, IManager oldManager, IManager newManager) internal {
    totalPosition[oldManager] -= pos;
    totalPosition[newManager] += pos;

    uint cap = totalPositionCap[newManager];
    if (cap != 0 && totalPosition[newManager] > cap) revert OT_ManagerChangeExceedCap();
  }

  function _takeOISnapshotPreTrade(uint subId, uint tradeId) internal {
    if (openInterestBeforeTrade[subId][tradeId].initialized) return;

    uint oi = openInterest[subId];
    openInterestBeforeTrade[subId][tradeId].initialized = true;
    openInterestBeforeTrade[subId][tradeId].oi = oi.toUint240();

    emit SnapshotTaken(subId, tradeId, oi);
  }

  /**
   * @dev update global OI for an subId, base on adjustment of a single account
   * @param preBalance Account balance before an adjustment
   * @param change Change of balance
   */
  function _updateOIAndTotalPosition(IManager manager, uint subId, int preBalance, int change) internal {
    int postBalance = preBalance + change;

    // update OI for subId
    openInterest[subId] =
      (openInterest[subId].toInt256() + SignedMath.max(0, postBalance) - SignedMath.max(0, preBalance)).toUint256();

    // update total position for manager, won't revert if it exceeds the cap, should only be checked by manager by the end of all transfers
    totalPosition[manager] = totalPosition[manager] + postBalance.abs() - preBalance.abs();
  }
}
