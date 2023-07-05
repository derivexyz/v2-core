// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../../src/feeds/LyraRateFeed.sol";

import "./LyraFeedTestUtils.sol";

contract UNIT_LyraRateFeed is LyraFeedTestUtils {
  LyraRateFeed feed;

  // signer
  uint private pk;
  address private pkOwner;

  uint referenceTime;
  uint64 defaultExpiry;

  function setUp() public {
    feed = new LyraRateFeed();

    // set signer
    pk = 0xBEEF;
    pkOwner = vm.addr(pk);

    vm.warp(block.timestamp + 365 days);
    referenceTime = block.timestamp;
    defaultExpiry = uint64(referenceTime + 365 days);

    feed.addSigner(pkOwner, true);
  }

  function testCanAddSigner() public {
    address alice = address(0xaaaa);
    feed.addSigner(alice, true);
    assertEq(feed.isSigner(alice), true);
  }

  function testCanPassInDataAndUpdateRateFeed() public {
    IBaseLyraFeed.FeedData memory feedData = _getDefaultRateData();
    feed.acceptData(_signFeedData(feed, pk, feedData));

    (int rate, uint confidence) = feed.getInterestRate(defaultExpiry);

    assertEq(rate, int(-0.1e18));
    assertEq(confidence, 1e18);
  }

  function testCantPassInInvalidConfidence() public {
    IBaseLyraFeed.FeedData memory feedData = _getDefaultRateData();
    feedData.data = abi.encode(defaultExpiry, -0.1e18, 1.01e18);
    bytes memory data = _signFeedData(feed, pk, feedData);

    vm.expectRevert(ILyraRateFeed.LRF_InvalidConfidence.selector);
    feed.acceptData(data);
  }

  function testCannotUpdateRateFeedFromInvalidSigner() public {
    // we don't whitelist the pk owner this time
    feed.addSigner(pkOwner, false);

    IBaseLyraFeed.FeedData memory feedData = _getDefaultRateData();
    bytes memory data = _signFeedData(feed, pk, feedData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidSigner.selector);
    feed.acceptData(data);
  }

  function testCannotUpdateRateFeedAfterDeadline() public {
    IBaseLyraFeed.FeedData memory feedData = _getDefaultRateData();
    bytes memory data = _signFeedData(feed, pk, feedData);

    vm.warp(block.timestamp + 10);

    vm.expectRevert(IBaseLyraFeed.BLF_DataExpired.selector);
    feed.acceptData(data);
  }

  function testCannotSetRateInTheFuture() public {
    IBaseLyraFeed.FeedData memory feedData = _getDefaultRateData();
    feedData.timestamp = uint64(block.timestamp + 1000);

    bytes memory data = _signFeedData(feed, pk, feedData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidTimestamp.selector);
    feed.acceptData(data);
  }

  function testIgnoreUpdateIfOlderDataIsPushed() public {
    IBaseLyraFeed.FeedData memory feedData = _getDefaultRateData();
    feed.acceptData(_signFeedData(feed, pk, feedData));

    // this data has the same timestamp, so it will be ignored
    feedData.data = abi.encode(defaultExpiry, 0.1e18, 1.01e18);
    feed.acceptData(_signFeedData(feed, pk, feedData));

    (int rate, uint confidence) = feed.getInterestRate(defaultExpiry);
    assertEq(rate, -0.1e18);
    assertEq(confidence, 1e18);
  }

  function testCannotSubmitPriceWithReplacedSigner() public {
    // use a different private key to sign the data but still specify pkOwner as signer
    uint pk2 = 0xBEEF2222;

    // replace pkOwner with random signer address
    IBaseLyraFeed.FeedData memory feedData = _getDefaultRateData();
    bytes memory data = _signFeedData(feed, pk2, feedData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidSignature.selector);
    feed.acceptData(data);
  }

  function _getDefaultRateData() internal view returns (IBaseLyraFeed.FeedData memory feedData) {
    // expiry, rate, confidence
    bytes memory rateData = abi.encode(defaultExpiry, -0.1e18, 1e18);

    return IBaseLyraFeed.FeedData({
      data: rateData,
      timestamp: uint64(block.timestamp),
      deadline: block.timestamp + 5,
      signer: pkOwner,
      signature: new bytes(0)
    });
  }
}
