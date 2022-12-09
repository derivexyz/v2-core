// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "test/feeds/mocks/MockV3Aggregator.sol";
import "src/feeds/ChainlinkSpotFeeds.sol";
contract TestChainlinkSpotFeeds is Test {
  ChainlinkSpotFeeds spotFeeds;
  MockV3Aggregator aggregator1;
  MockV3Aggregator aggregator2;

  bytes32 pair1 = "ETH/USD";
  bytes32 pair2 = "BTC/USD";

  function setUp() public {
    aggregator1 = new MockV3Aggregator(8, 1000e18);
    aggregator2 = new MockV3Aggregator(18, 10000e18);
    spotFeeds = new ChainlinkSpotFeeds();
  }
  
  //////////////////
  // Adding Feeds //
  //////////////////

  function testEmptyFeedId() public {
    spotFeeds.addFeed(pair1, address(aggregator1));
    spotFeeds.addFeed(pair2, address(aggregator2));

    /* test empty feedId */
    (AggregatorV3Interface aggregatorResult, uint8 decimalResult) = spotFeeds.aggregators(1000001);
    assertEq(address(aggregatorResult), address(0));
    assertEq(decimalResult, 0);
  }

  function testAddMultipleFeeds() public {
    /* variable setting */
    AggregatorV3Interface aggregatorResult;
    uint8 decimalResult;

    /* test first spot price */
    spotFeeds.addFeed(pair1, address(aggregator1));
    /* check result */
    assertEq(spotFeeds.lastFeedId(), 1);
    (aggregatorResult, decimalResult) = spotFeeds.aggregators(1);
    assertEq(address(aggregatorResult), address(aggregator1));
    assertEq(decimalResult, 8);

    /* test second spot price */
    spotFeeds.addFeed(pair2, address(aggregator2));
    /* check result */
    assertEq(spotFeeds.lastFeedId(), 2);
    (aggregatorResult, decimalResult) = spotFeeds.aggregators(2);
    assertEq(address(aggregatorResult), address(aggregator2));
    assertEq(decimalResult, 18);
  }

  ////////////////////////
  // Getting Spot Price //
  ////////////////////////

  function testGetSpotWithFeedId() public {}

  function testGetSpotWithTradingPair() public {}

  //////////////////////////
  // Getting Feed Details //
  //////////////////////////

  function testGetFeedId() public {}

  function testGetTradingPair() public {}

}
