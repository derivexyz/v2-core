// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "test/feeds/mocks/MockV3Aggregator.sol";
import "src/feeds/ChainlinkSpotFeeds.sol";
contract TestChainlinkSpotFeeds is Test {
  ChainlinkSpotFeeds spotFeeds;
  MockV3Aggregator aggregator1;
  MockV3Aggregator aggregator2;

  function setUp() public {
    aggregator1 = new MockV3Aggregator(8, 1000e18);
    aggregator2 = new MockV3Aggregator(18, 10000e18);
    spotFeeds = new ChainlinkSpotFeeds();
  }
  
  //////////////////
  // Adding Feeds //
  //////////////////

  function testAddMultipleFeeds() {}

  ////////////////////////
  // Getting Spot Price //
  ////////////////////////

  function testGetSpotWithFeedId() {}

  function testGetSpotWithTradingPair() {}

  //////////////////////////
  // Getting Feed Details //
  //////////////////////////

  function getFeedId() {}

  function getTradingPair() {}

}
