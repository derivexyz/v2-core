// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface ILyraSpotDiffFeed {
  struct SpotDiffData {
    int128 spotDiff;
    uint64 confidence;
    uint64 timestamp;
    // the latest timestamp you can use this data
    uint deadline;
    // signature v, r, s
    address signer;
    bytes signature;
  }

  /// @dev structure to store in contract storage
  struct SpotDiffDetail {
    int128 spotDiff;
    uint64 confidence;
    uint64 timestamp;
  }

  ////////////////////////
  //       Events       //
  ////////////////////////
  event SpotDiffUpdated(address indexed signer, int128 spotDiff, uint64 confidence, uint64 timestamp);

  ////////////////////////
  //       Errors       //
  ////////////////////////
  error LSF_InvalidConfidence();
}
