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
    aggregator1 = new MockV3Aggregator(8, 1000e8);
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

  function testFailInvalidAggregatorAddition() public {
    spotFeeds.addFeed(symbol1, address(0), 1 hours);
    vm.expectRevert(
      abi.encodeWithSelector(ChainlinkSpotFeeds.SF_InvalidAggregator.selector)
    );
  }

  function testFailInvalidStaleLimit() public {
    spotFeeds.addFeed(symbol1, address(aggregator2), 0);
    vm.expectRevert(
      abi.encodeWithSelector(ChainlinkSpotFeeds.SF_StaleLimitCannotBeZero.selector)
    );
  }

  ////////////////////////
  // Getting Spot Price //
  ////////////////////////

  function testFailGetSpotWhenInvalidAggregator() public {
    _addAllFeeds();
    spotFeeds.getSpot(1000001);
    vm.expectRevert(
      abi.encodeWithSelector(ChainlinkSpotFeeds.SF_InvalidAggregator.selector)
    );
  }

  function testFailGetSpotWhenStale() public {
    _addAllFeeds();
    uint oldTime = block.timestamp;
    skip(1 hours + 1 minutes);
    spotFeeds.getSpot(1);
    vm.expectRevert(
      abi.encodeWithSelector(
        ChainlinkSpotFeeds.SF_SpotFeedStale.selector,
        oldTime, block.timestamp, 1 hours)
    );
  }

  function testGetSpotWithFeedId() public {
    _addAllFeeds();

    /* get correct initial feed */
    uint ethSpotPrice = spotFeeds.getSpot(1);
    uint btcSpotPrice = spotFeeds.getSpot(2);
    assertEq(ethSpotPrice, 1000e18);
    assertEq(btcSpotPrice, 10000e18);
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
