// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {ISpotFeed} from "./ISpotFeed.sol";
import {IBaseLyraFeed} from "./IBaseLyraFeed.sol";

interface ILyraSpotDiffFeed is IBaseLyraFeed {
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
  event SpotDiffUpdated(int96 spotDiff, uint96 confidence, uint64 timestamp);

  ////////////////////////
  //       Errors       //
  ////////////////////////
  error LSDF_InvalidConfidence();
}
