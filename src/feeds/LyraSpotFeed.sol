// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

// inherited
import "./BaseLyraFeed.sol";

// interfaces
import {ISpotFeed} from "../interfaces/ISpotFeed.sol";
import {ILyraSpotFeed} from "../interfaces/ILyraSpotFeed.sol";

/**
 * @title LyraSpotFeed
 * @author Lyra
 * @notice Spot feed that takes off-chain updates, verify signature and update on-chain
 */
contract LyraSpotFeed is BaseLyraFeed, ILyraSpotFeed, ISpotFeed {
  // Pack the following into 1 storage slot
  SpotDetail private spotDetail;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor() BaseLyraFeed("LyraSpotFeed", "1") {}

  ////////////////////////
  //  Public Functions  //
  ////////////////////////

  /**
   * @notice Gets spot price
   * @return spotPrice Spot price with 18 decimals.
   */
  function getSpot() public view returns (uint, uint) {
    _checkNotStale(spotDetail.timestamp);

    return (spotDetail.price, spotDetail.confidence);
  }

  /**
   * @notice Parse input data and update spot price
   */
  function acceptData(bytes calldata data) external override {
    FeedData memory feedData = _parseAndVerifyFeedData(data);

    if (feedData.timestamp <= spotDetail.timestamp) return;

    // ignore if timestamp is lower or equal to current
    (uint96 price, uint64 confidence) = abi.decode(feedData.data, (uint96, uint64));

    if (confidence > 1e18) revert LSF_InvalidConfidence();

    // update spot price
    spotDetail = SpotDetail(price, confidence, uint64(feedData.timestamp));

    emit SpotPriceUpdated(price, confidence, uint64(feedData.timestamp));
  }
}
