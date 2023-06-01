// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "openzeppelin/utils/math/SignedMath.sol";
import "openzeppelin/utils/math/SafeCast.sol";

import "src/interfaces/IGlobalSubIdOITracking.sol";

/**
 * @title GlobalSubIdOITracking
 * @notice Contract helping assets to track OI and total supply globally for each subId
 */
contract GlobalSubIdOITracking is IGlobalSubIdOITracking {
  using SafeCast for uint;
  using SafeCast for int;

  ///@dev SubId => tradeId => open interest snapshot
  mapping(uint subId => mapping(uint tradeId => SubIdOISnapshot)) public openInterestBeforeTrade;

  ///@dev Open interest for a subId. OI is the sum of all positive balance
  mapping(uint subId => uint) public openInterest;

  /**
   * @dev Take snapshot of total OI before a trade
   */
  function _takeSubIdOISnapshotPreTrade(uint subId, uint tradeId) internal {
    if (openInterestBeforeTrade[subId][tradeId].initialized) return;

    uint oi = openInterest[subId];

    openInterestBeforeTrade[subId][tradeId] = SubIdOISnapshot({initialized: true, oi: oi.toUint240()});

    emit SubIdSnapshotTaken(subId, tradeId, oi);
  }

  /**
   * @dev update global OI for an subId
   * @param preBalance Account balance before an adjustment
   * @param change Change of balance
   */
  function _updateSubIdOI(uint subId, int preBalance, int change) internal {
    int postBalance = preBalance + change;

    // update OI for subId
    openInterest[subId] =
      (openInterest[subId].toInt256() + SignedMath.max(0, postBalance) - SignedMath.max(0, preBalance)).toUint256();
  }
}
