// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./LyraFeedTestUtils.sol";

import "src/feeds/LyraVolFeed.sol";
import "src/feeds/LyraForwardFeed.sol";
import "../../shared/mocks/MockFeeds.sol";

/**
 * @dev we deploy actual Account contract in these tests to simplify verification process
 */
contract UNIT_LyraForwardFeed is LyraFeedTestUtils {
  MockFeeds mockSpot;
  LyraForwardFeed feed;

  bytes32 domainSeparator;

  // signer
  uint private pk;
  address private pkOwner;
  uint referenceTime;
  uint64 defaultExpiry;

  // default variables
  int96 fwdSpotDifference = 10e18;
  uint settlementStartAggregate;
  uint currentSpotAggregate;
  uint defaultConfidence = 1e18;

  function setUp() public {
    mockSpot = new MockFeeds();
    mockSpot.setSpot(990e18, 1e18);

    feed = new LyraForwardFeed(ISpotFeed(address(mockSpot)));

    domainSeparator = feed.domainSeparator();

    // set signer
    pk = 0xBEEF;
    pkOwner = vm.addr(pk);

    vm.warp(block.timestamp + 365 days);
    referenceTime = block.timestamp;
    defaultExpiry = uint64(referenceTime + 365 days);

    feed.addSigner(pkOwner, true);

    settlementStartAggregate = 1050e18 * uint(defaultExpiry - feed.SETTLEMENT_TWAP_DURATION());
    currentSpotAggregate = 1050e18 * uint(defaultExpiry);
  }

  function testSetSettlementHeartBeat() public {
    feed.setSettlementHeartbeat(30 minutes);
    assertEq(feed.settlementHeartbeat(), 30 minutes);
  }

  function testSetNewSpotFeed() public {
    MockFeeds newSpotFeed = new MockFeeds();
    newSpotFeed.setSpot(1500e18, 1e18);

    feed.setSpotFeed(newSpotFeed);
    assertEq(address(feed.spotFeed()), address(newSpotFeed));
  }

  function testRevertsWhenFetchingInvalidExpiry() public {
    vm.expectRevert(ILyraForwardFeed.LFF_MissingExpiryData.selector);
    feed.getForwardPrice(defaultExpiry);
  }

  function testCanPassInDataAndUpdateFwdFeed() public {
    IBaseLyraFeed.FeedData memory feedData = _getDefaultForwardData();
    bytes memory data = _signFeedData(feed, pk, feedData);

    feed.acceptData(data);

    (uint fwdPrice, uint confidence) = feed.getForwardPrice(defaultExpiry);
    assertEq(fwdPrice, 1000e18);
    assertEq(confidence, 1e18);
  }

  function testCannotGetInvalidForwardDiff() public {
    IBaseLyraFeed.FeedData memory feedData = _getDefaultForwardData();

    int newDiff = -1000e18;
    feedData.data =
      abi.encode(defaultExpiry, settlementStartAggregate, currentSpotAggregate, newDiff, defaultConfidence);
    feed.acceptData(_signFeedData(feed, pk, feedData));

    vm.expectRevert("SafeCast: value must be positive");
    feed.getForwardPrice(defaultExpiry);

    vm.warp(block.timestamp + 1);

    // but can return 0
    newDiff = -990e18;
    feedData.data =
      abi.encode(defaultExpiry, settlementStartAggregate, currentSpotAggregate, newDiff, defaultConfidence);

    feedData.timestamp += 1;
    feed.acceptData(_signFeedData(feed, pk, feedData));
    (uint fwdPrice,) = feed.getForwardPrice(defaultExpiry);
    assertEq(fwdPrice, 0);
  }

  function testCannotUpdateFwdFeedFromInvalidSigner() public {
    // we didn't whitelist the pk owner this time
    feed.addSigner(pkOwner, false);

    IBaseLyraFeed.FeedData memory feedData = _getDefaultForwardData();
    bytes memory data = _signFeedData(feed, pk, feedData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidSigner.selector);
    feed.acceptData(data);
  }

  function testCannotUpdateFwdFeedAfterDeadline() public {
    IBaseLyraFeed.FeedData memory feedData = _getDefaultForwardData();
    bytes memory data = _signFeedData(feed, pk, feedData);

    vm.warp(block.timestamp + 10);

    vm.expectRevert(IBaseLyraFeed.BLF_DataExpired.selector);
    feed.acceptData(data);
  }

  function testCannotSetFwdInTheFuture() public {
    IBaseLyraFeed.FeedData memory feedData = _getDefaultForwardData();
    feedData.timestamp = uint64(block.timestamp + 1000);
    bytes memory data = _signFeedData(feed, pk, feedData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidTimestamp.selector);
    feed.acceptData(data);
  }

  function testCannotSetFwdPastExpiry() public {
    vm.warp(defaultExpiry + 1);
    IBaseLyraFeed.FeedData memory feedData = _getDefaultForwardData();
    feedData.timestamp = uint64(defaultExpiry + 1);
    bytes memory data = _signFeedData(feed, pk, feedData);

    vm.expectRevert(ILyraForwardFeed.LFF_InvalidFwdDataTimestamp.selector);
    feed.acceptData(data);
  }

  function testCanSetSettlementData() public {
    vm.warp(defaultExpiry);
    IBaseLyraFeed.FeedData memory feedData = _getDefaultForwardData();
    feedData.timestamp = uint64(defaultExpiry);
    bytes memory data = _signFeedData(feed, pk, feedData);
    feed.acceptData(data);

    (bool settled, uint settlementPrice) = feed.getSettlementPrice(defaultExpiry);
    assertEq(settlementPrice, 1050e18);
    assertTrue(settled);
  }

  function testIgnoreUpdateIfOlderDataIsPushed() public {
    IBaseLyraFeed.FeedData memory feedData = _getDefaultForwardData();

    bytes memory data = _signFeedData(feed, pk, feedData);
    feed.acceptData(data);
    (, uint confidence) = feed.getForwardPrice(defaultExpiry);
    assertEq(confidence, 1e18);

    // update confidence
    uint newConfidence = 0.9e18;
    feedData.data =
      abi.encode(defaultExpiry, settlementStartAggregate, currentSpotAggregate, fwdSpotDifference, newConfidence);
    feedData.timestamp = uint64(block.timestamp - 100);
    data = _signFeedData(feed, pk, feedData);
    feed.acceptData(data);
    (, confidence) = feed.getForwardPrice(defaultExpiry);

    assertEq(confidence, 1e18);
  }

  function testSplitForwardFeed() public {
    feed.setHeartbeat(1 days);

    vm.warp(defaultExpiry - 10 minutes);
    IBaseLyraFeed.FeedData memory feedData = _getDefaultForwardData();
    uint newCurAggregate = 1050e18 * uint(defaultExpiry - 10 minutes);

    feedData.data =
      abi.encode(defaultExpiry, settlementStartAggregate, newCurAggregate, fwdSpotDifference, defaultConfidence);
    feedData.timestamp = uint64(block.timestamp);

    // update confidence
    uint newConfidence = 0.99e18;
    feedData.data =
      abi.encode(defaultExpiry, settlementStartAggregate, newCurAggregate, fwdSpotDifference, newConfidence);

    bytes memory data = _signFeedData(feed, pk, feedData);
    feed.acceptData(data);

    (uint forwardFixedPortion, uint forwardVariablePortion, uint confidence) =
      feed.getForwardPricePortions(defaultExpiry);
    assertEq(forwardFixedPortion, uint(1050e18) * 2 / 3);
    assertEq(forwardVariablePortion, uint(1000e18) / 3);
    assertEq(confidence, 0.99e18);

    vm.warp(defaultExpiry - 4 minutes);
    vm.expectRevert(ILyraForwardFeed.LFF_SettlementDataTooOld.selector);
    feed.getForwardPricePortions(defaultExpiry);

    vm.warp(defaultExpiry);
    (bool settled,) = feed.getSettlementPrice(defaultExpiry);
    assertEq(settled, false);
  }

  function testCannotSubmitPriceWithReplacedSigner() public {
    // use a different private key to sign the data but still specify pkOwner as signer
    uint pk2 = 0xBEEF2222;

    IBaseLyraFeed.FeedData memory feedData = _getDefaultForwardData();
    bytes memory data = _signFeedData(feed, pk2, feedData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidSignature.selector);
    feed.acceptData(data);
  }

  function testCanGetFixedSettlementPriceAfterExpiry() public {
    feed.setHeartbeat(10 minutes);
    // set a forward price entry as settlement data
    vm.warp(defaultExpiry);
    IBaseLyraFeed.FeedData memory feedData = _getDefaultForwardData();
    feedData.timestamp = uint64(defaultExpiry);
    bytes memory data = _signFeedData(feed, pk, feedData);
    feed.acceptData(data);

    vm.warp(block.timestamp + 50 minutes);
    (uint forwardFixedPortion, uint forwardVariablePortion,) = feed.getForwardPricePortions(defaultExpiry);

    assertEq(forwardFixedPortion, 1050e18);
    assertEq(forwardVariablePortion, 0);
  }

  function setHeartBeat() public {
    feed.setHeartbeat(1 days);
    assertEq(feed.settlementHeartbeat(), 1 days);
  }

  function testCannotSetInvalidSettlementData() public {
    vm.warp(defaultExpiry - 10 minutes);
    IBaseLyraFeed.FeedData memory feedData = _getDefaultForwardData();

    uint newCurAggregate = 0;
    feedData.data =
      abi.encode(defaultExpiry, newCurAggregate, currentSpotAggregate, fwdSpotDifference, defaultConfidence);
    bytes memory data = _signFeedData(feed, pk, feedData);

    vm.expectRevert(ILyraForwardFeed.LFF_InvalidSettlementData.selector);
    feed.acceptData(data);
  }

  function testCannotSetInvalidForwardConfidence() public {
    IBaseLyraFeed.FeedData memory feedData = _getDefaultForwardData();

    // update confidence
    uint newConfidence = 1.01e18;
    feedData.data =
      abi.encode(defaultExpiry, settlementStartAggregate, currentSpotAggregate, fwdSpotDifference, newConfidence);
    bytes memory data = _signFeedData(feed, pk, feedData);

    vm.expectRevert(ILyraForwardFeed.LFF_InvalidConfidence.selector);
    feed.acceptData(data);
  }

  function _getDefaultForwardData() internal view returns (IBaseLyraFeed.FeedData memory) {
    return IBaseLyraFeed.FeedData({
      data: abi.encode(
        defaultExpiry, settlementStartAggregate, currentSpotAggregate, fwdSpotDifference, defaultConfidence
        ),
      timestamp: uint64(block.timestamp),
      deadline: block.timestamp + 5,
      signer: pkOwner,
      signature: new bytes(0)
    });
  }
}
