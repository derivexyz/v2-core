// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "src/feeds/TokenFeedV2.sol";
import "src/Accounts.sol";
import "test/feeds/mocks/MockV3Aggregator.sol";
import "src/feeds/ChainlinkSpotFeeds.sol";

import "test/shared/mocks/MockManager.sol";
import "test/shared/mocks/MockERC20.sol";

/**
 * @dev test price feed
 */
contract UNIT_PriceFeed is Test {
  TokenFeedV2 feed;
  Accounts account;

  ChainlinkSpotFeeds spotFeeds;
  MockV3Aggregator aggregator;

  int public constant BIG_PRICE = 1e42;
  uint expiry = block.timestamp + 2 weeks;
  uint strike = 1000e18;
  uint callId;
  uint putId;

  function setUp() public {
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    uint assetFeedId = _setupChainlinkFeeds();
    feed = new TokenFeedV2(spotFeeds, assetFeedId);
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
    vm.expectRevert(abi.encodeWithSelector(ITokenFeedV2.SettlementPriceAlreadySet.selector, expiry, uint(answer)));
    feed.setSettlementPrice(expiry);
  }

  function _setupChainlinkFeeds() public returns (uint) {
    aggregator = new MockV3Aggregator(18, 1000e18);
    spotFeeds = new ChainlinkSpotFeeds();
    uint feedId = spotFeeds.addFeed("ETH/USD", address(aggregator), 1 hours);
    aggregator.updateRoundData(1, 1000e18, block.timestamp, block.timestamp, 1);
    return feedId;
  }

  function _updateChainlinkData(int spotPrice, uint80 roundId) internal {
    aggregator.updateRoundData(roundId, spotPrice, block.timestamp, block.timestamp, roundId);
  }
}
