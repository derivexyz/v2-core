// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ICashAsset {
  ////////////////
  //   Errors   //
  ////////////////

  /// @dev caller is not account
  error CA_NotAccount();

  /// @dev caller is not the liquidation module
  error CA_NotLiquidationModule();

  /// @dev revert when user trying to upgrade to a unknown manager
  error CA_UnknownManager();

  /// @dev caller is not owner of the account
  error CA_OnlyAccountOwner();

  /// @dev accrued interest is stale
  error CA_InterestAccrualStale(uint lastUpdatedAt, uint currentTimestamp);
}
