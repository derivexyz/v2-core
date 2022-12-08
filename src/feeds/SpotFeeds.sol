// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/interfaces/ISpotFeeds.sol";

// Adapter condenses all deposited positions into a single position per subId
contract SpotFeeds is ISpotFeeds {
  ///////////////
  // Variables //
  ///////////////

  mapping(bytes32 => uint) tradingPairToFeedId;
  mapping(uint => bytes32) feedIdToTradingPair;

  ////////////
  // Events //
  ////////////

  // todo: add events

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor() Owned {}

  ///////////////
  // Get Price //
  ///////////////

  /**
   * @notice Gets spot price for a given feedId
   * @param feedId id set for a given trading pair
   * @return spotPrice 18 decimal price of trading pair
   */
  function getSpot(uint feedId) external returns (uint spotPrice) {
    return _getSpot(feedId);
  }

  /**
   * @notice Gets spot price for a given tradingPair
   * @param pair bytes that returns the trading pair (e.g. "ETH/USDC")
   * @return spotPrice 18 decimal price of trading pair
   */
  function getSpot(bytes32 pair) external returns (uint spotPrice) {
    return _getSpot(tradingPairToFeedId[pair]);
  }

  /**
   * @notice Uses chainlinks `AggregatorV3` oracles to retrieve price.
   *         The price is always converted to an 18 decimal uint
   * @param feedId id set for a given trading pair
   * @return spotPrice 18 decimal price of trading pair
   */
  function _getSpot(uint feedId) internal returns (uint spotPrice) {
    // todo: integrate with chainlink
  }

  //////////////////
  // Adding feeds //
  //////////////////

  /**
   * @notice Assigns a trading pair to a given feedId and chainlink aggregator
   * @param pair bytes that returns the trading pair (e.g. "ETH/USDC")
   * @return feedId id set for a given trading pair
   */
  function addFeed(bytes32 pair, address chainlinkAggregator) external returns (uint feedId) {
    // todo: integrate with chainlink
  }

  //////////
  // View //
  //////////

  /**
   * @notice Returns feedId for a given pair
   * @param pair bytes that returns the trading pair (e.g. "ETH/USDC")
   * @return feedId id of the feed
   */
  function getFeedId(bytes32 pair) external view returns (uint feedId) {
    return tradingPairToFeedId[pair];
  }

  /**
   * @notice Returns the pair name for a given feedId
   * @param feedId id of the feed
   * @return pair bytes that returns the trading pair (e.g. "ETH/USDC")
   */
  function getTradingPair(uint feedId) external view returns (bytes32 pair) {
    return feedIdToTradingPair[feedId];
  }

  ////////////
  // Errors //
  ////////////
}
