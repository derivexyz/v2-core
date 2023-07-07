// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface IAllowList {
  struct AllowListDetails {
    uint64 timestamp;
    bool allowed;
  }

  ////////////////////////
  //     Functions      //
  ////////////////////////
  function canTrade(address user) external view returns (bool);

  ////////////////////////
  //       Events       //
  ////////////////////////
  event AllowListEnabled(bool enabled);
  event AllowListUpdated(address indexed user, AllowListDetails details);
}
