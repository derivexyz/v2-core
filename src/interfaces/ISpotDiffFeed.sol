// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

/**
 * @title ISpotDiffFeed
 * @author Lyra
 * @notice Returns a value that represents a divergence from the spot price. E.g. perp price might be +$50 from spot.
 */
interface ISpotDiffFeed {
  /**
   * @notice Gets spot price and confidence
   * @return spotDiff 18 decimal price divergence from spot.
   */
  function getSpotDiff() external view returns (int128 spotDiff, uint64 confidence);
}
