// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

/**
 * @title ISpotFeed
 * @author Lyra
 * @notice Spot feed adapter for Chainlink aggregators.
 *         NOTE: `spotPrice` always assumed to return 18 decimal place uint
 */
interface ISpotFeed {
  /**
   * @notice Gets spot price and confidence
   * @return spotPrice 18 decimal price of trading pair.
   */
  function getSpot() external view returns (uint spotPrice, uint confidence);
}