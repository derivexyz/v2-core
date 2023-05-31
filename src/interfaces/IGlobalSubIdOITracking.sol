// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface IGlobalSubIdOITracking {
  struct SubIdOISnapshot {
    bool initialized;
    uint240 oi;
  }

  function openInterestBeforeTrade(uint subId, uint tradeId) external view returns (bool, uint240);
  function openInterest(uint subId) external view returns (uint);

  /// @dev Emitted when oi is snapshot for given subId
  event SubIdSnapshotTaken(uint subId, uint tradeId, uint oi);
}
