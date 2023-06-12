// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {ISpotFeed} from "./ISpotFeed.sol";

interface ILyraSpotDiffFeed {
  struct SpotDiffData {
    int96 spotDiff;
    uint64 confidence;
    // the latest timestamp you can use this data
    uint64 timestamp;
    uint deadline;
    address signer;
    bytes signature;
  }

  /// @dev structure to store in contract storage
  struct SpotDiffDetail {
    int96 spotDiff;
    uint64 confidence;
    uint64 timestamp;
  }

  ////////////////////////
  //       Events       //
  ////////////////////////
  event SpotFeedUpdated(ISpotFeed spotFeed);
  event SpotDiffUpdated(address indexed signer, int96 spotDiff, uint96 confidence, uint64 timestamp);

  ////////////////////////
  //       Errors       //
  ////////////////////////
  error LSDF_InvalidConfidence();
}
