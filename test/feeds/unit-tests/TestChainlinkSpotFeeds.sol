// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "test/feeds/mocks/MockV3Aggregator.sol";
import "src/feeds/ChainlinkSpotFeeds.sol";

contract TestChainlinkSpotFeeds is Test {
  ChainlinkSpotFeeds spotFeeds;
  MockV3Aggregator aggregator1;
  MockV3Aggregator aggregator2;

  bytes32 symbol1 = "ETH/USD";
  bytes32 symbol2 = "BTC/USD";

  function setUp() public {
    aggregator1 = new MockV3Aggregator(8, 1000e18);
    aggregator2 = new MockV3Aggregator(18, 10000e18);
    spotFeeds = new ChainlinkSpotFeeds();
  }

  //////////////////
  // Adding Feeds //
  //////////////////

  function testEmptyFeedId() public {
    spotFeeds.addFeed(symbol1, address(aggregator1), 1 hours);
    spotFeeds.addFeed(symbol2, address(aggregator2), 2 hours);

    /* test empty feedId */
    (AggregatorV3Interface aggregatorResult, uint8 decimalResult, uint64 staleLimit) = spotFeeds.aggregators(1000001);
    assertEq(address(aggregatorResult), address(0));
    assertEq(decimalResult, 0);
    assertEq(staleLimit, 0);

    // todo: expect revert
  }

  function testAddMultipleFeeds() public {
    /* variable setting */
    AggregatorV3Interface aggregatorResult;
    uint8 decimalResult;
    uint64 staleLimit;

    /* test first spot price */
    spotFeeds.addFeed(symbol1, address(aggregator1), 1 hours);
    /* check result */
    assertEq(spotFeeds.lastFeedId(), 1);
    (aggregatorResult, decimalResult, staleLimit) = spotFeeds.aggregators(1);
    assertEq(address(aggregatorResult), address(aggregator1));
    assertEq(decimalResult, 8);
    assertEq(staleLimit, 1 hours);

    /* test second spot price */
    spotFeeds.addFeed(symbol2, address(aggregator2), 2 hours);
    /* check result */
    assertEq(spotFeeds.lastFeedId(), 2);
    (aggregatorResult, decimalResult, staleLimit) = spotFeeds.aggregators(2);
    assertEq(address(aggregatorResult), address(aggregator2));
    assertEq(decimalResult, 18);
    assertEq(staleLimit, 2 hours);
  }

  ////////////////////////
  // Getting Spot Price //
  ////////////////////////

  function testGetSpotWithFeedId() public {
    _addAllFeeds();

    /* get correct initial feed */
    spotFeeds.getSpot(1);

    // todo: test once spot price logic is implemented
  }

  //////////////////////////
  // Getting Feed Details //
  //////////////////////////

  function testGetSymbol() public {
    _addAllFeeds();
    assertEq(spotFeeds.getSymbol(1), "ETH/USD");
    assertEq(spotFeeds.getSymbol(2), "BTC/USD");
  }

  function _addAllFeeds() internal {
    spotFeeds.addFeed(symbol1, address(aggregator1), 1 hours);
    spotFeeds.addFeed(symbol2, address(aggregator2), 2 hours);
  }
}
