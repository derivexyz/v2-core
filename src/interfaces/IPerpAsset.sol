// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./IAsset.sol";

interface IPerpAsset is IAsset {
  ////////////////
  //   Errors   //
  ////////////////

  /// @dev caller is not account
  error PA_NotAccount();

  /// @dev caller is not the liquidation module
  error PA_NotLiquidationModule();

  /// @dev revert when user trying to upgrade to a unknown manager
  error PA_UnknownManager();

  /// @dev caller is not owner of the account
  error PA_OnlyAccountOwner();
}
