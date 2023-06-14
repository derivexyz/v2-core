// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

// libraries
import "openzeppelin/utils/math/Math.sol";
import "openzeppelin/utils/math/SafeCast.sol";

// inherited
import "src/feeds/BaseLyraFeed.sol";

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
  bytes32 public constant SPOT_DIFF_DATA_TYPEHASH = keccak256(
    "SpotDiffData(int96 spotDiff,uint64 confidence,uint64 timestamp,uint256 deadline,address signer,bytes signature)"
  );

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
    SpotDiffData memory diffData = abi.decode(data, (SpotDiffData));
    // verify signature
    bytes32 structHash = hashSpotDiffData(diffData);

    _verifySignatureDetails(diffData.signer, structHash, diffData.signature, diffData.deadline, diffData.timestamp);

    // ignore if timestamp is lower or equal to current
    if (diffData.timestamp <= spotDiffDetails.timestamp) return;

    if (diffData.confidence > 1e18) {
      revert LSDF_InvalidConfidence();
    }

    // update spotDiff
    spotDiffDetails = SpotDiffDetail(diffData.spotDiff, diffData.confidence, diffData.timestamp);

    emit SpotDiffUpdated(diffData.signer, diffData.spotDiff, diffData.confidence, diffData.timestamp);
  }

  function hashSpotDiffData(SpotDiffData memory diffData) public pure returns (bytes32) {
    return keccak256(abi.encode(SPOT_DIFF_DATA_TYPEHASH, diffData.spotDiff, diffData.confidence, diffData.timestamp));
  }
}
