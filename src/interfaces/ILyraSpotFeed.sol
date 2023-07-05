// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface ILyraSpotFeed {
  /// @dev structure to store in contract storage
  struct SpotDetail {
    uint96 price;
    uint64 confidence;
    uint64 timestamp;
  }

  ////////////////////////
  //       Events       //
  ////////////////////////
  event SpotPriceUpdated(address indexed signer, uint96 spot, uint96 confidence, uint64 timestamp);

  ////////////////////////
  //       Errors       //
  ////////////////////////
  error LSF_InvalidConfidence();
}
