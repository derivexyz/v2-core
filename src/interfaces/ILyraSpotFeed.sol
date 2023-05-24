// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface ILyraSpotFeed {
  struct SpotData {
    // price data
    uint128 price;
    uint64 confidence;
    uint64 timestamp;
    // the latest timestamp you can use this data
    uint deadline;
    // signature v, r, s
    address signer;
    bytes signature;
  }

  /// @dev structure to store in contract storage
  struct SpotDetail {
    uint128 price;
    uint64 confidence;
    uint64 timestamp;
  }

  ////////////////////////
  //       Events       //
  ////////////////////////
  event SpotPriceUpdated(address indexed signer, uint128 spot, uint64 confidence, uint64 timestamp);

  ////////////////////////
  //       Errors       //
  ////////////////////////
  error LSF_InvalidConfidence();
}
