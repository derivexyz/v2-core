// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

// libraries
import "openzeppelin/utils/math/SignedMath.sol";
import "openzeppelin/utils/math/Math.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "lyra-utils/decimals/SignedDecimalMath.sol";

// inherited
import "./BaseLyraFeed.sol";

// interfaces
import {ILyraSpotDiffFeed} from "../interfaces/ILyraSpotDiffFeed.sol";
import {ISpotDiffFeed} from "../interfaces/ISpotDiffFeed.sol";
import {ISpotFeed} from "../interfaces/ISpotFeed.sol";

/**
 * @title LyraSpotDiffFeed
 * @author Lyra
 * @notice Feed that returns the total of a spot feed and the updated feed value
 */
contract LyraSpotDiffFeed is BaseLyraFeed, ILyraSpotDiffFeed, ISpotDiffFeed {
  using SignedDecimalMath for int;
  ////////////////////////
  //     Variables      //
  ////////////////////////

  ISpotFeed public spotFeed;
  /// @dev spotDiffCap Cap the value returned based on a percentage of the spot price
  int public spotDiffCap = 0.1e18;

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

  function setSpotDiffCap(uint _spotDiffCap) external onlyOwner {
    if (_spotDiffCap > 1e18) revert LSDF_InvalidSpotDiffCap();
    spotDiffCap = SafeCast.toInt256(_spotDiffCap);
    emit SpotDiffCapUpdated(_spotDiffCap);
  }

  ////////////////////////
  //  Public Functions  //
  ////////////////////////

  /**
   * @notice Gets the combination of spot diff and spot
   */
  function getResult() public view returns (uint, uint) {
    (uint spot, uint spotConfidence) = spotFeed.getSpot();
    int spotInt = SafeCast.toInt256(spot);

    SpotDiffDetail memory diffDetails = spotDiffDetails;
    _checkNotStale(diffDetails.timestamp);

    int spotDiff = int(diffDetails.spotDiff);
    int maxDiff = spotInt.multiplyDecimal(spotDiffCap);
    int res = spotInt;
    if (spotDiff >= 0) {
      res += spotDiff < maxDiff ? spotDiff : maxDiff;
    } else {
      res += spotDiff > -maxDiff ? spotDiff : -maxDiff;
    }

    return (SafeCast.toUint256(res), Math.min(spotConfidence, diffDetails.confidence));
  }

  /**
   * @notice Parse input data and update spotDiff
   */
  function acceptData(bytes calldata data) external override {
    FeedData memory feedData = _parseAndVerifyFeedData(data);

    // ignore if timestamp is lower or equal to current
    if (feedData.timestamp <= spotDiffDetails.timestamp) return;

    (int96 spotDiff, uint64 confidence) = abi.decode(feedData.data, (int96, uint64));

    if (confidence > 1e18) revert LSDF_InvalidConfidence();

    // update spotDiff
    spotDiffDetails = SpotDiffDetail(spotDiff, confidence, feedData.timestamp);

    emit SpotDiffUpdated(spotDiff, confidence, feedData.timestamp);
  }
}
