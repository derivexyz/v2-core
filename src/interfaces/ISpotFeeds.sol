// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title ISpotFeeds
 * @author Lyra
 * @notice Spot feed adapter interface intended to be inherited
 *         by a variety of feed options, including Chainlink aggregators.
 *         NOTE: spotPrice always assumed to return 18 decimal place uint
 */

interface ISpotFeeds {
  /**
   * @notice Gets spot price for a given feedId
   * @param feedId id set for a given trading pair
   * @return spotPrice 18 decimal price of trading pair
   */
  function getSpot(uint feedId) external returns (uint spotPrice);

  /**
   * @notice Gets spot price for a given tradingPair
   * @param pair bytes that returns the trading pair (e.g. "ETH/USDC")
   * @return spotPrice 18 decimal price of trading pair
   */
  function getSpot(bytes32 pair) external returns (uint spotPrice);

  /**
   * @notice Returns feedId for a given pair
   * @param pair bytes that returns the trading pair (e.g. "ETH/USDC")
   * @return feedId id of the feed
   */
  function getFeedId(bytes32 pair) external view returns (uint feedId);

  /**
   * @notice Returns the pair name for a given feedId
   * @param feedId id of the feed
   * @return pair bytes that returns the trading pair (e.g. "ETH/USDC")
   */
  function getTradingPair(uint feedId) external view returns (bytes32 pair);
}
