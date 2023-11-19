// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import {IBaseLyraFeed} from "./IBaseLyraFeed.sol";

interface ILyraSpotFeed is IBaseLyraFeed {
  /// @dev structure to store in contract storage
  struct SpotDetail {
    uint96 price;
    uint64 confidence;
    uint64 timestamp;
  }

  ////////////////////////
  //       Events       //
  ////////////////////////
  event SpotPriceUpdated(uint96 spot, uint96 confidence, uint64 timestamp);

  ////////////////////////
  //       Errors       //
  ////////////////////////
  error LSF_InvalidConfidence();
}
