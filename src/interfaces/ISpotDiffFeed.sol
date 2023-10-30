// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ISpotFeed} from "./ISpotFeed.sol";

/**
 * @title ISpotDiffFeed
 * @author Lyra
 * @notice Returns the sum of a given feed value and the spot price
 */
interface ISpotDiffFeed {
  function spotFeed() external view returns (ISpotFeed);

  /**
   * @notice Gets summed resulting feed value and minimum confidence between the two feeds
   * @dev The value must be >= 0 (the feed is supposed to be within a few % of spot generally)
   * @return result 18 decimal combination of spot price and spotDiff
   */
  function getResult() external view returns (uint result, uint confidence);
}
