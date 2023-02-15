// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "test/feeds/mocks/MockV3Aggregator.sol";
import "src/feeds/ChainlinkSpotFeed.sol";

contract UNIT_TestChainlinkSpotFeed18Decimals is Test {
  ChainlinkSpotFeed feed;
  MockV3Aggregator aggregator;

  uint expiry = block.timestamp + 2 hours;

  function setUp() public {
    aggregator = new MockV3Aggregator(18, 1000e18);
    feed = new ChainlinkSpotFeed(aggregator, 1 hours);
  }

  ////////////////////////
  // Getting Spot Price //
  ////////////////////////

  function testCannotGetSpotWhenStale() public {
    uint oldTime = block.timestamp;
    skip(1 hours + 1 minutes);
    vm.expectRevert(
      abi.encodeWithSelector(IChainlinkSpotFeed.CF_SpotFeedStale.selector, oldTime, block.timestamp, 1 hours)
    );
    feed.getSpot();
  }

  function testGetSpot() public {
    /* get correct initial feed */
    uint ethSpotPrice = feed.getSpot();
    assertEq(ethSpotPrice, 1000e18);
  }

  function testDetectCarriedOverFeed() public {
    /* add a carried over feed */
    skip(3 hours);
    _updateFeed(2, 500e18, 1);

    /* should revert since answer carried over from stale round */
    (uint spotPrice, uint updatedAt) = feed.getSpotAndUpdatedAt();
    assertEq(spotPrice, 500e18);
    assertEq(updatedAt, block.timestamp - 3 hours);
  }

  function testCanSetSettlementPrice() external {
    assertEq(feed.getSettlementPrice(expiry), 0);

    // Fast forward to expiry and update feed
    vm.warp(expiry);
    _updateChainlinkData(1200e18, 2);

    // Lock in settlement price
    feed.setSettlementPrice(expiry);

    // Assert settled price same as feed
    (, int answer,,,) = aggregator.latestRoundData();
    assertEq(feed.getSettlementPrice(expiry), uint(answer));
  }

  function testCannotSetSettlementPriceOnFutureExpiry() external {
    // Should revert because we have not reached expiry time
    vm.expectRevert(abi.encodeWithSelector(ISettlementFeed.NotExpired.selector, expiry, block.timestamp));
    feed.setSettlementPrice(expiry);
  }

  function testCannotSettlePriceAlreadySet() external {
    // First confirm that the settlement price hasn't been set for callId
    assertEq(feed.getSettlementPrice(expiry), 0);

    // Fast forward to expiry and update feed
    vm.warp(expiry);
    _updateChainlinkData(1200e18, 2);

    // Lock in settlement price for callId
    feed.setSettlementPrice(expiry);

    // Assert settled price same as feed
    (, int answer,,,) = aggregator.latestRoundData();
    assertEq(feed.getSettlementPrice(expiry), uint(answer));

    // cannot set the same expiry twice
    vm.expectRevert(
      abi.encodeWithSelector(IChainlinkSpotFeed.CF_SettlementPriceAlreadySet.selector, expiry, uint(answer))
    );
    feed.setSettlementPrice(expiry);
  }

  function _updateChainlinkData(int spotPrice, uint80 roundId) internal {
    aggregator.updateRoundData(roundId, spotPrice, block.timestamp, block.timestamp, roundId);
  }

  /////////////
  // Helpers //
  /////////////

  function _updateFeed(uint80 roundId, int spotPrice, uint80 answeredInRound) internal {
    aggregator.updateRoundData(roundId, spotPrice, block.timestamp, block.timestamp, answeredInRound);
  }
}

contract UNIT_TestChainlinkSpotFeed8Decimals is Test {
  ChainlinkSpotFeed feed;
  MockV3Aggregator aggregator;

  uint expiry = block.timestamp + 2 hours;

  function setUp() public {
    aggregator = new MockV3Aggregator(8, 1000e8);
    feed = new ChainlinkSpotFeed(aggregator, 1 hours);
  }

  function testGetSpot() public {
    /* get correct initial feed */
    uint ethSpotPrice = feed.getSpot();
    assertEq(ethSpotPrice, 1000e18);
  }
}
