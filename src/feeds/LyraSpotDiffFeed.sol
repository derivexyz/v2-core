// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

// inherited
import "src/feeds/BaseLyraFeed.sol";

// interfaces
import "src/interfaces/ILyraSpotDiffFeed.sol";
import "src/interfaces/ISpotDiffFeed.sol";

/**
 * @title LyraSpotDiffFeed
 * @author Lyra
 * @notice Spot divergence feed that takes off-chain updates, verify signature and update on-chain
 */
contract LyraSpotDiffFeed is BaseLyraFeed, ILyraSpotDiffFeed, ISpotDiffFeed {
  bytes32 public constant SPOT_DIFF_DATA_TYPEHASH = keccak256(
    "SpotDiffData(int128 spotDiff,uint64 confidence,uint64 timestamp,uint256 deadline,address signer,bytes signature)"
  );

  // pack the following into 1 storage slot
  SpotDiffDetail private spotDiffDetails;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor() BaseLyraFeed("LyraSpotDiffFeed", "1") {}

  ////////////////////////
  //  Public Functions  //
  ////////////////////////

  /**
   * @notice Gets spot price
   * @return spotPrice Spot price with 18 decimals.
   */
  function getSpotDiff() public view returns (int128, uint64) {
    SpotDiffDetail memory spot = spotDiffDetails;

    return (spot.spotDiff, spot.confidence);
  }

  /**
   * @notice Parse input data and update spot price
   */
  function acceptData(bytes calldata data) external override {
    // parse data as SpotData
    SpotDiffData memory spotDiffData = abi.decode(data, (SpotDiffData));
    // verify signature
    bytes32 structHash = hashSpotDiffData(spotDiffData);

    _verifySignatureDetails(
      spotDiffData.signer, structHash, spotDiffData.signature, spotDiffData.deadline, spotDiffData.timestamp
    );

    // ignore if timestamp is lower or equal to current
    if (spotDiffData.timestamp <= spotDiffDetails.timestamp) return;

    if (spotDiffData.confidence > 1e18) {
      revert LSF_InvalidConfidence();
    }

    // update spot price
    spotDiffDetails = SpotDiffDetail(spotDiffData.spotDiff, spotDiffData.confidence, spotDiffData.timestamp);

    emit SpotDiffUpdated(spotDiffData.signer, spotDiffData.spotDiff, spotDiffData.confidence, spotDiffData.timestamp);
  }

  /**
   * @dev return the hash of the spotDiffData object
   */
  function hashSpotDiffData(SpotDiffData memory spotDiffData) public pure returns (bytes32) {
    return keccak256(
      abi.encode(SPOT_DIFF_DATA_TYPEHASH, spotDiffData.spotDiff, spotDiffData.confidence, spotDiffData.timestamp)
    );
  }
}
