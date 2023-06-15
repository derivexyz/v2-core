// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

// libraries
import "openzeppelin/utils/math/Math.sol";
import "openzeppelin/utils/math/SafeCast.sol";

// inherited
import "./BaseLyraFeed.sol";

// interfaces
import {ILyraSpotDiffFeed} from "../interfaces/ILyraSpotDiffFeed.sol";
import {IInterestRateFeed} from "../interfaces/IInterestRateFeed.sol";
import {ISpotDiffFeed} from "../interfaces/ISpotDiffFeed.sol";
import {ISpotFeed} from "../interfaces/ISpotFeed.sol";

/**
 * @title LyraSpotDiffFeed
 * @author Lyra
 * @notice Feed that returns the total of a spot feed and the updated feed value
 */
contract LyraSpotDiffFeed is BaseLyraFeed, ILyraSpotDiffFeed, ISpotDiffFeed {
  ISpotFeed public spotFeed;

  SpotDiffDetail public spotDiffDetails;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(ISpotFeed _spotFeed) BaseLyraFeed("LyraSpotDiffFeed", "1") {
    spotFeed = _spotFeed;
    emit SpotFeedUpdated(_spotFeed);
  }

  ///////////
  // Admin //
  ///////////

  function setSpotFeed(ISpotFeed _spotFeed) external onlyOwner {
    spotFeed = _spotFeed;
    emit SpotFeedUpdated(_spotFeed);
  }

  ////////////////////////
  //  Public Functions  //
  ////////////////////////

  /**
   * @notice Gets the combination of spot diff and spot
   */
  function getResult() public view returns (uint, uint) {
    (uint spot, uint spotConfidence) = spotFeed.getSpot();

    SpotDiffDetail memory diffDetails = spotDiffDetails;
    _checkNotStale(diffDetails.timestamp);

    uint res = SafeCast.toUint256(SafeCast.toInt256(spot) + int(diffDetails.spotDiff));

    return (res, Math.min(spotConfidence, diffDetails.confidence));
  }

  /**
   * @notice Parse input data and update spotDiff
   */
  function acceptData(bytes calldata data) external override {
    // parse data as SpotDiffData
    FeedData memory feedData = abi.decode(data, (FeedData));
    // verify signature
    _verifyFeedData(feedData);

    // ignore if timestamp is lower or equal to current
    if (feedData.timestamp <= spotDiffDetails.timestamp) return;

    (int96 spotDiff, uint64 confidence) = abi.decode(feedData.data, (int96, uint64));

    if (confidence > 1e18) revert LSDF_InvalidConfidence();

    // update spotDiff
    spotDiffDetails = SpotDiffDetail(spotDiff, confidence, feedData.timestamp);

    emit SpotDiffUpdated(feedData.signer, spotDiff, confidence, feedData.timestamp);
  }
}
