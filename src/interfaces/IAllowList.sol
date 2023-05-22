// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface IAllowList {
  struct AllowListDetails {
    uint64 timestamp;
    bool allowed;
  }

  struct AllowListData {
    address user;
    bool allowed;
    // timestamp is required to prevent replay attack
    uint64 timestamp;
    uint deadline;
    address signer;
    bytes signature;
  }

  ////////////////////////
  //     Functions      //
  ////////////////////////
  function canTrade(address user) external view returns (bool);

  ////////////////////////
  //       Events       //
  ////////////////////////
  event AllowListEnabled(bool enabled);
  event AllowListUpdated(address indexed signer, address indexed user, AllowListDetails details);
}
