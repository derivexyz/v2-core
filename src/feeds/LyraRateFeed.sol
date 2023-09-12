// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

// inherited
import "./BaseLyraFeed.sol";

// interfaces
import {ILyraRateFeed} from "../interfaces/ILyraRateFeed.sol";
import {IInterestRateFeed} from "../interfaces/IInterestRateFeed.sol";

/**
 * @title LyraRateFeed
 * @author Lyra
 * @notice Rate feed that takes off-chain updates, verify signature and update on-chain
 */
contract LyraRateFeed is BaseLyraFeed, ILyraRateFeed, IInterestRateFeed {

  ////////////////////////
  //     Variables      //
  ////////////////////////

  mapping(uint64 expiry => RateDetail) private rateDetails;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor() BaseLyraFeed("LyraRateFeed", "1") {}

  ////////////////////////
  //  Public Functions  //
  ////////////////////////

  /**
   * @notice Gets rate
   * @return ratePrice Rate with 18 decimals.
   */
  function getInterestRate(uint64 expiry) public view returns (int, uint) {
    RateDetail memory rateDetail = rateDetails[expiry];

    _checkNotStale(rateDetail.timestamp);

    return (rateDetail.rate, rateDetail.confidence);
  }

  /**
   * @notice Parse input data and update rate
   */
  function acceptData(bytes calldata data) external override {
    FeedData memory feedData = _parseAndVerifyFeedData(data);

    (uint64 expiry, int96 rate, uint64 confidence) = abi.decode(feedData.data, (uint64, int96, uint64));

    // ignore if timestamp is lower or equal to current
    if (feedData.timestamp <= rateDetails[expiry].timestamp) return;

    if (confidence > 1e18) {
      revert LRF_InvalidConfidence();
    }

    // update rate
    rateDetails[expiry] = RateDetail(rate, confidence, feedData.timestamp);

    emit RateUpdated(expiry, rate, confidence, feedData.timestamp);
  }
}
