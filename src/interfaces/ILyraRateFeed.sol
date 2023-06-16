// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface ILyraRateFeed {
  /// @dev structure to store in contract storage
  struct RateDetail {
    int96 rate;
    uint64 confidence;
    uint64 timestamp;
  }

  ////////////////////////
  //       Events       //
  ////////////////////////
  event RateUpdated(address indexed signer, uint64 indexed expiry, int96 rate, uint96 confidence, uint64 timestamp);

  ////////////////////////
  //       Errors       //
  ////////////////////////
  error LRF_InvalidConfidence();
}
