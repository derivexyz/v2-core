// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./IAsset.sol";
import "./IInterestRateModel.sol";
import "./ISettlementFeed.sol";

interface IOption is IAsset, ISettlementFeed {
  /////////////////
  //   Structs   //
  /////////////////

  struct OISnapshot {
    bool initialized;
    uint240 oi;
  }

  ///////////////////
  //   Functions   //
  ///////////////////

  function openInterestBeforeTrade(uint subId, uint tradeId) external view returns (bool initialized, uint240 oi);

  function openInterest(uint subId) external view returns (uint oi);

  ////////////////
  //   Events   //
  ////////////////

  /// @dev Emitted when a manager address is whitelisted or unwhitelisted
  event WhitelistManagerSet(address manager, bool whitelisted);

  /// @dev Emitted when interest related state variables are updated
  event SnapshotTaken(uint subId, uint tradeId, uint oi);

  ////////////////
  //   Errors   //
  ////////////////

  /// @dev revert if caller is not Accounts
  error OA_NotAccounts();

  /// @dev revert when settlement is triggered from unknown managers
  error OA_UnknownManager();
}
