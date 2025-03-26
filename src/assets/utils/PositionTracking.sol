// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "openzeppelin/utils/math/SignedMath.sol";
import "openzeppelin/access/Ownable2Step.sol";
import "openzeppelin/utils/math/SafeCast.sol";

import {IPositionTracking} from "../../interfaces/IPositionTracking.sol";
import {IManager} from "../../interfaces/IManager.sol";

/**
 * @title PositionTracking
 * @author Lyra
 * @notice Contract helping assets to track total position size for each manager.
 *         Total Position = sum of all positive & negative balances
 * @dev    Managers must check the position cap themselves
 */
contract PositionTracking is Ownable2Step, IPositionTracking {
  using SafeCast for uint;
  using SafeCast for int;

  /// @dev Cap on each manager's max position sum. This aggregates .abs() of all opened position
  mapping(IManager => uint) public totalPositionCap;

  /// @dev Each manager's max position sum. This aggregates .abs() of all opened position
  mapping(IManager manager => uint) public totalPosition;

  /// @dev Snapshot of total position before a trade, used to determine if a trade increases or decreases total position
  mapping(IManager manager => mapping(uint tradeId => OISnapshot)) public totalPositionBeforeTrade;

  constructor() Ownable(msg.sender) {}

  /////////////////////
  //   Owner-only    //
  /////////////////////

  function setTotalPositionCap(IManager manager, uint cap) external onlyOwner {
    totalPositionCap[manager] = cap;

    emit TotalPositionCapSet(address(manager), cap);
  }

  /////////////////////
  //    Internal     //
  /////////////////////

  /**
   * @dev Update total position for a manager, base on adjustment of a single account
   * @param preBalance Account balance before an adjustment
   * @param change Change of balance
   */
  function _updateTotalPositions(IManager manager, int preBalance, int change) internal {
    int postBalance = preBalance + change;

    // update total position for manager, won't revert if it exceeds the cap, should only be checked by manager by the end of all transfers
    totalPosition[manager] = totalPosition[manager] + SignedMath.abs(postBalance) - SignedMath.abs(preBalance);
  }

  /**
   * @dev Take snapshot of total position before a trade
   */
  function _takeTotalPositionSnapshotPreTrade(IManager manager, uint tradeId) internal {
    if (totalPositionBeforeTrade[manager][tradeId].initialized) return;

    uint oi = totalPosition[manager];

    totalPositionBeforeTrade[manager][tradeId] = OISnapshot({initialized: true, oi: oi.toUint240()});

    emit SnapshotTaken(address(manager), tradeId, oi);
  }
}
