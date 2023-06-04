// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface ILyraRateFeed {
  struct RateData {
    uint64 expiry;
    int96 rate;
    uint64 confidence;
    uint64 timestamp;
    // the latest timestamp you can use this data
    uint deadline;
    // signature v, r, s
    address signer;
    bytes signature;
  }

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
