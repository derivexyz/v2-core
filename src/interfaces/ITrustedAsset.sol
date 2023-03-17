// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ITrustedAsset {
  

  ////////////////
  //   Events   //
  ////////////////

  event WhitelistManagerSet(address _manager, bool _whitelisted);


  ////////////////
  //   Errors   //
  ////////////////

  /// @dev caller is not account
  error TA_NotAccount();

  /// @dev revert when user trying to upgrade to a unknown manager
  error TA_UnknownManager();

}
