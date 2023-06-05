// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "openzeppelin/utils/math/SignedMath.sol";
import "openzeppelin/access/Ownable2Step.sol";
import "openzeppelin/utils/math/SafeCast.sol";

import {IPositionTracking} from "src/interfaces/IPositionTracking.sol";
import {IManager} from "src/interfaces/IManager.sol";

/**
 * @title PositionTracking
 * @author Lyra
 * @notice contract helping assets to track OI and total supply, useful for charging fees, caps.. etc
 */
contract PositionTracking is Ownable2Step, IPositionTracking {
  using SafeCast for uint;
  using SafeCast for int;

  /// @dev Cap on each manager's max position sum. This aggregates .abs() of all opened position
  mapping(IManager => uint) public totalPositionCap;

  /// @dev Each manager's max position sum. This aggregates .abs() of all opened position
  mapping(IManager manager => uint) public totalPosition;

  mapping(IManager manager => mapping(uint tradeId => OISnapshot)) public totalPositionBeforeTrade;

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

  /**
   * @dev update global OI for an subId, base on adjustment of a single account - note manager must check if it exceeds the cap
   * @param preBalance Account balance before an adjustment
   * @param change Change of balance
   */
  function _updateTotalOI(IManager manager, int preBalance, int change) internal {
    int postBalance = preBalance + change;

    // update total position for manager, won't revert if it exceeds the cap, should only be checked by manager by the end of all transfers
    totalPosition[manager] = totalPosition[manager] + SignedMath.abs(postBalance) - SignedMath.abs(preBalance);
  }

  /**
   * @dev Take snapshot of total OI before a trade
   */
  function _takeTotalOISnapshotPreTrade(IManager manager, uint tradeId) internal {
    if (totalPositionBeforeTrade[manager][tradeId].initialized) return;

    uint oi = totalPosition[manager];

    totalPositionBeforeTrade[manager][tradeId] = OISnapshot({initialized: true, oi: oi.toUint240()});

    emit SnapshotTaken(address(manager), tradeId, oi);
  }

  /**
   * @dev Move OI from one manager to another, to be called in manager change hook of the asset inheriting this.
   */
  function _migrateManagerOI(uint pos, IManager oldManager, IManager newManager) internal {
    totalPosition[oldManager] -= pos;
    totalPosition[newManager] += pos;

    if (totalPosition[newManager] > totalPositionCap[newManager]) {
      revert OIT_CapExceeded();
    }
  }
}
