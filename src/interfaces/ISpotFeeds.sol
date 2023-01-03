// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title ISpotFeeds
 * @author Lyra
 * @notice Spot feed adapter interface intended to be inherited
 *         by a variety of feed options, including Chainlink aggregators.
 *         NOTE: `spotPrice` always assumed to return 18 decimal place uint
 */

interface ISpotFeeds {
  /**
   * @notice Gets spot price for a given feedId
   * @param feedId ID set for a given trading pair
   * @return spotPrice 18 decimal price of trading pair
   */
  function getSpot(uint feedId) external returns (uint spotPrice);

  /**
   * @notice Returns the pair name for a given feedId
   * @param feedId ID of the feed
   * @return symbol Bytes that returns the trading pair (e.g. "ETH/USDC")
   */
  function getSymbol(uint feedId) external view returns (bytes32 symbol);
}
