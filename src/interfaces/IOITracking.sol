// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IManager} from "src/interfaces/IManager.sol";

interface IOITracking {
  /////////////////
  //   Structs   //
  /////////////////

  struct OISnapshot {
    bool initialized;
    uint240 oi;
  }

  function openInterestBeforeTrade(uint subId, uint tradeId) external view returns (bool initialized, uint240 oi);

  function openInterest(uint subId) external view returns (uint oi);

  function totalPositionCap(IManager manager) external view returns (uint);

  function totalPosition(IManager manager) external view returns (uint);

  ////////////////
  //   Events   //
  ////////////////

  /// @dev Emitted when interest related state variables are updated
  event SnapshotTaken(uint subId, uint tradeId, uint oi);

  /// @dev Emitted when OI cap is set
  event TotalPositionCapSet(address manager, uint oiCap);

  ////////////////
  //   Errors   //
  ////////////////

  /// @dev total position cap reached while changing manager
  error OT_ManagerChangeExceedCap();
}
