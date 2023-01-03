// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ICashAsset {
  ////////////////
  //   Errors   //
  ////////////////

  /// @dev caller is not account
  error LA_NotAccount();

  /// @dev revert when user trying to upgrade to a unknown manager
  error LA_UnknownManager();

  /// @dev caller is not owner of the account
  error LA_OnlyAccountOwner();

  /// @dev accrued interest is stale
  error LA_InterestAccrualStale(uint lastUpdatedAt, uint currentTimestamp);
}
