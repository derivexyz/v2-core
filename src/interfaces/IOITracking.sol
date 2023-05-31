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

  function setTotalPositionCap(IManager manager, uint oiCap) external;
  function totalPositionCap(IManager manager) external view returns (uint);
  function totalPositionBeforeTrade(IManager manager, uint tradeId) external view returns (bool, uint240);
  function totalPosition(IManager manager) external view returns (uint);

  ////////////////
  //   Events   //
  ////////////////

  /// @dev Emitted when snapshot is taken for totalOi
  event SnapshotTaken(address manager, uint tradeId, uint oi);

  /// @dev Emitted when OI cap is set
  event TotalPositionCapSet(address manager, uint oiCap);
}
