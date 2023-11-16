// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "../../../src/feeds/LyraSpotFeed.sol";
import "./LyraFeedTestUtils.sol";

contract UNIT_LyraSpotFeed is LyraFeedTestUtils {
  LyraSpotFeed feed;

  bytes32 domainSeparator;

  // signer
  uint private pk;
  address private pkOwner;

  function setUp() public {
    feed = new LyraSpotFeed();
    domainSeparator = feed.domainSeparator();

    // set signer
    pk = 0xBEEF;
    pkOwner = vm.addr(pk);

    vm.warp(block.timestamp + 365 days);
    feed.addSigner(pkOwner, true);
  }

  function testCanPassInDataAndUpdateSpotFeed() public {
    IBaseLyraFeed.FeedData memory spotData = _getDefaultSpotData();
    bytes memory data = _signFeedData(feed, pk, spotData);

    feed.acceptData(data);

    (uint spot, uint confidence) = feed.getSpot();

    assertEq(spot, 1000e18);
    assertEq(confidence, 1e18);
  }

  function testCantPassInInvalidConfidence() public {
    IBaseLyraFeed.FeedData memory spotData = _getDefaultSpotData();

    // change confidence
    spotData.data = abi.encode(1100e18, 1.01e18);

    bytes memory data = _signFeedData(feed, pk, spotData);

    vm.expectRevert(ILyraSpotFeed.LSF_InvalidConfidence.selector);
    feed.acceptData(data);
  }

  function testCannotUpdateSpotFeedFromInvalidSigner() public {
    // we don't whitelist the pk owner this time
    feed.addSigner(pkOwner, false);

    IBaseLyraFeed.FeedData memory spotData = _getDefaultSpotData();
    bytes memory data = _signFeedData(feed, pk, spotData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidSigner.selector);
    feed.acceptData(data);
  }

  function testCannotUpdateSpotFeedAfterDeadline() public {
    IBaseLyraFeed.FeedData memory spotData = _getDefaultSpotData();
    bytes memory data = _signFeedData(feed, pk, spotData);

    vm.warp(block.timestamp + 10);

    vm.expectRevert(IBaseLyraFeed.BLF_DataExpired.selector);
    feed.acceptData(data);
  }

  function testCannotSetSpotInTheFuture() public {
    IBaseLyraFeed.FeedData memory spotData = _getDefaultSpotData();
    spotData.timestamp = uint64(block.timestamp + 1000);

    bytes memory data = _signFeedData(feed, pk, spotData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidTimestamp.selector);
    feed.acceptData(data);
  }

  function testIgnoreUpdateIfOlderDataIsPushed() public {
    IBaseLyraFeed.FeedData memory spotData = _getDefaultSpotData();
    bytes memory data1 = _signFeedData(feed, pk, spotData);

    feed.acceptData(data1);

    spotData.data = abi.encode(1100e18, 1.01e18);

    // this data has the same timestamp, so it will be ignored
    bytes memory data2 = _signFeedData(feed, pk, spotData);
    feed.acceptData(data2);

    (uint spot, uint confidence) = feed.getSpot();
    assertEq(spot, 1000e18);
    assertEq(confidence, 1e18);
  }

  function testCannotSubmitPriceWithReplacedSigner() public {
    // use a different private key to sign the data but still specify pkOwner as signer
    uint pk2 = 0xBEEF2222;

    // replace pkOwner with random signer address
    IBaseLyraFeed.FeedData memory spotData = _getDefaultSpotData();
    spotData.signers[0] = pkOwner;
    bytes memory data = _signFeedData(feed, pk2, spotData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidSignature.selector);
    feed.acceptData(data);
  }

  function testCannotReadStaleData() public {
    IBaseLyraFeed.FeedData memory spotData = _getDefaultSpotData();
    bytes memory data = _signFeedData(feed, pk, spotData);
    feed.acceptData(data);

    vm.warp(block.timestamp + feed.heartbeat() + 1);

    vm.expectRevert(IBaseLyraFeed.BLF_DataTooOld.selector);
    feed.getSpot();
  }

  function _getDefaultSpotData() internal view returns (IBaseLyraFeed.FeedData memory) {
    uint96 price = 1000e18;
    uint64 confidence = 1e18;
    bytes memory spotData = abi.encode(price, confidence);

    return IBaseLyraFeed.FeedData({
      data: spotData,
      timestamp: uint64(block.timestamp),
      deadline: block.timestamp + 5,
      signers: new address[](1),
      signatures: new bytes[](1)
    });
  }
}
