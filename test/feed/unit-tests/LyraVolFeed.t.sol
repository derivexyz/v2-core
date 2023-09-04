// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./LyraFeedTestUtils.sol";

import "lyra-utils/math/Black76.sol";
import "../../../src/feeds/LyraVolFeed.sol";

/**
 * @dev we deploy actual Account contract in these tests to simplify verification process
 */
contract UNIT_LyraVolFeed is LyraFeedTestUtils {
  LyraVolFeed feed;

  bytes32 domainSeparator;

  // signer
  uint private pk;
  address private pkOwner;
  uint referenceTime;
  uint64 defaultExpiry;

  function setUp() public {
    feed = new LyraVolFeed();

    domainSeparator = feed.domainSeparator();

    // set signer
    pk = 0xBEEF;
    pkOwner = vm.addr(pk);

    vm.warp(block.timestamp + 365 days);
    referenceTime = block.timestamp;
    defaultExpiry = uint64(referenceTime + 365 days);

    feed.addSigner(pkOwner, true);
  }

  function testRevertsWhenFetchingInvalidExpiry() public {
    vm.expectRevert(ILyraVolFeed.LVF_MissingExpiryData.selector);
    feed.getVol(uint128(uint(1500e18)), defaultExpiry);
  }

  function testCannotPassInTimestampHigherThanExpiry() public {
    IBaseLyraFeed.FeedData memory volData = _getDefaultVolData();

    vm.warp(defaultExpiry + 1);

    volData.timestamp = uint64(defaultExpiry + 1);
    volData.deadline = uint64(defaultExpiry + 1);
    bytes memory data = _signFeedData(feed, pk, volData);

    vm.expectRevert(ILyraVolFeed.LVF_InvalidVolDataTimestamp.selector);
    feed.acceptData(data);
  }

  function testCannotGetVolWithNoData() public {
    vm.expectRevert(ILyraVolFeed.LVF_MissingExpiryData.selector);
    feed.getExpiryMinConfidence(defaultExpiry);
  }

  function testCanPassInDataAndUpdateVolFeed() public {
    IBaseLyraFeed.FeedData memory volData = _getDefaultVolData();
    bytes memory data = _signFeedData(feed, pk, volData);

    feed.acceptData(data);

    (uint vol, uint confidence) = feed.getVol(uint128(uint(1500e18)), defaultExpiry);
    assertApproxEqAbs(vol, 1.1728e18, 0.0001e18);
    assertEq(confidence, 1e18);
  }

  function testCannotUpdateVolFeedFromInvalidSigner() public {
    // we didn't whitelist the pk owner this time
    feed.addSigner(pkOwner, false);

    IBaseLyraFeed.FeedData memory volData = _getDefaultVolData();
    bytes memory data = _signFeedData(feed, pk, volData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidSigner.selector);
    feed.acceptData(data);
  }

  function testCannotUpdateVolFeedAfterDeadline() public {
    IBaseLyraFeed.FeedData memory volData = _getDefaultVolData();
    bytes memory data = _signFeedData(feed, pk, volData);

    vm.warp(block.timestamp + 10);

    vm.expectRevert(IBaseLyraFeed.BLF_DataExpired.selector);
    feed.acceptData(data);
  }

  function testCannotSetVolInTheFuture() public {
    IBaseLyraFeed.FeedData memory volData = _getDefaultVolData();
    volData.timestamp = uint64(block.timestamp + 1000);
    bytes memory data = _signFeedData(feed, pk, volData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidTimestamp.selector);
    feed.acceptData(data);
  }

  function testIgnoreUpdateIfOlderDataIsPushed() public {
    IBaseLyraFeed.FeedData memory volData = _getDefaultVolData();

    bytes memory data = _signFeedData(feed, pk, volData);
    feed.acceptData(data);
    uint confidence = feed.getExpiryMinConfidence(defaultExpiry);
    assertEq(confidence, 1e18);

    volData.data = abi.encode(defaultExpiry, 0, 0, 0, 0, 0, 0, 0, 1.2e18);
    volData.timestamp = uint64(block.timestamp - 100);
    data = _signFeedData(feed, pk, volData);
    feed.acceptData(data);

    confidence = feed.getExpiryMinConfidence(defaultExpiry);

    assertEq(confidence, 1e18);
  }

  function testCannotSubmitPriceWithReplacedSigner() public {
    // use a different private key to sign the data but still specify pkOwner as signer
    uint pk2 = 0xBEEF2222;

    IBaseLyraFeed.FeedData memory volData = _getDefaultVolData();
    volData.signers[0] = pkOwner;
    bytes memory data = _signFeedData(feed, pk2, volData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidSignature.selector);
    feed.acceptData(data);
  }

  function _getDefaultVolData() internal view returns (IBaseLyraFeed.FeedData memory) {
    int SVI_a = 1e18;
    uint SVI_b = 1.5e18;
    int SVI_rho = -0.1e18;
    int SVI_m = -0.05e18;
    uint SVI_sigma = 0.05e18;
    uint SVI_fwd = 1200e18;
    uint64 SVI_refTau = uint64(Black76.annualise(uint64(defaultExpiry - block.timestamp)));
    uint64 confidence = 1e18;

    // example data: a = 1, b = 1.5, sig = 0.05, rho = -0.1, m = -0.05
    bytes memory volData =
      abi.encode(defaultExpiry, SVI_a, SVI_b, SVI_rho, SVI_m, SVI_sigma, SVI_fwd, SVI_refTau, confidence);
    return IBaseLyraFeed.FeedData({
      data: volData,
      timestamp: uint64(block.timestamp),
      deadline: block.timestamp + 5,
      signers: new address[](1),
      signatures: new bytes[](1)
    });
  }
}
