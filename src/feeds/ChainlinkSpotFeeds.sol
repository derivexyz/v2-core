// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/interfaces/ISpotFeeds.sol";
import "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract ChainlinkSpotFeeds is ISpotFeeds {
  /* only 1x SLOAD when getting price */
  struct Aggregator {
    // address of chainlink aggregator
    AggregatorV3Interface aggregator;
    // decimal units of returned spot price
    uint8 decimals;
  }

  ///////////////
  // Variables //
  ///////////////

  /// @dev maps feedId to tradingPair
  mapping(uint => bytes32) public feedIdToSymbol;

  /// @dev first id starts from 1
  uint public lastFeedId;
  /// @dev maps feedId to aggregator details
  mapping(uint => Aggregator) public aggregators;

  ////////////
  // Events //
  ////////////

  // todo: add events

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor() {}

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
   * @param symbol bytes that returns the trading pair (e.g. "ETH/USDC")
   * @return feedId id set for a given trading pair
   */
  function addFeed(bytes32 symbol, address chainlinkAggregator) external returns (uint feedId) {
    feedId = ++lastFeedId;

    /* store decimals once to reduce external calls during getSpotPrice */
    aggregators[feedId] = Aggregator({
      aggregator: AggregatorV3Interface(chainlinkAggregator),
      decimals: AggregatorV3Interface(chainlinkAggregator).decimals()
    });
    feedIdToSymbol[feedId] = symbol;
  }

  //////////
  // View //
  //////////

  /**
   * @notice Returns the pair name for a given feedId
   * @param feedId id of the feed
   * @return symbol bytes that returns the trading pair (e.g. "ETH/USDC")
   */
  function getSymbol(uint feedId) external view returns (bytes32 symbol) {
    return feedIdToSymbol[feedId];
  }

  ////////////
  // Errors //
  ////////////
}
