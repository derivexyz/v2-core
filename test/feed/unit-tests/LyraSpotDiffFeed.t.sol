// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "src/feeds/LyraVolFeed.sol";
import "src/feeds/LyraSpotDiffFeed.sol";
import "../../shared/mocks/MockFeeds.sol";

/**
 * @dev we deploy actual Account contract in these tests to simplify verification process
 */
contract UNIT_LyraSpotDiffFeed is Test {
  MockFeeds private mockSpot;
  LyraSpotDiffFeed private feed;

  bytes32 private domainSeparator;

  // signer
  uint private pk;
  address private pkOwner;

  function setUp() public {
    mockSpot = new MockFeeds();
    mockSpot.setSpot(990e18, 1e18);

    feed = new LyraSpotDiffFeed(ISpotFeed(address(mockSpot)));

    domainSeparator = feed.domainSeparator();

    // set signer
    pk = 0xBEEF;
    pkOwner = vm.addr(pk);

    vm.warp(block.timestamp + 365 days);

    feed.addSigner(pkOwner, true);
  }

  function testCanPassInDataAndUpdateSpotDiffFeed() public {
    ILyraSpotDiffFeed.SpotDiffData memory spotDiffData = _getDefaultSpotDiffData();
    bytes memory data = _getSignedSpotDiffData(pk, spotDiffData);

    feed.acceptData(data);

    (uint result, uint confidence) = feed.getResult();
    assertEq(result, 1000e18);
    assertEq(confidence, 1e18);
  }

  function testCannotGetInvalidForwardDiff() public {
    ILyraSpotDiffFeed.SpotDiffData memory spotDiffData = _getDefaultSpotDiffData();
    spotDiffData.spotDiff = -1000e18;
    feed.acceptData(_getSignedSpotDiffData(pk, spotDiffData));

    vm.expectRevert("SafeCast: value must be positive");
    feed.getResult();

    vm.warp(block.timestamp + 1);

    // but can return 0
    spotDiffData.spotDiff = -990e18;
    spotDiffData.timestamp += 1;
    feed.acceptData(_getSignedSpotDiffData(pk, spotDiffData));
    (uint res,) = feed.getResult();
    assertEq(res, 0);
  }

  function testCannotUpdateSpotDiffFeedFromInvalidSigner() public {
    // we didn't whitelist the pk owner this time
    feed.addSigner(pkOwner, false);

    ILyraSpotDiffFeed.SpotDiffData memory spotDiffData = _getDefaultSpotDiffData();
    bytes memory data = _getSignedSpotDiffData(pk, spotDiffData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidSigner.selector);
    feed.acceptData(data);
  }

  function testCannotUpdateSpotDiffFeedAfterDeadline() public {
    ILyraSpotDiffFeed.SpotDiffData memory spotDiffData = _getDefaultSpotDiffData();
    bytes memory data = _getSignedSpotDiffData(pk, spotDiffData);

    vm.warp(block.timestamp + 10);

    vm.expectRevert(IBaseLyraFeed.BLF_DataExpired.selector);
    feed.acceptData(data);
  }

  function testCannotSetSpotDiffInTheFuture() public {
    ILyraSpotDiffFeed.SpotDiffData memory spotDiffData = _getDefaultSpotDiffData();
    spotDiffData.timestamp = uint64(block.timestamp + 1000);
    bytes memory data = _getSignedSpotDiffData(pk, spotDiffData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidTimestamp.selector);
    feed.acceptData(data);
  }


  function testIgnoreUpdateIfOlderDataIsPushed() public {
    ILyraSpotDiffFeed.SpotDiffData memory spotDiffData = _getDefaultSpotDiffData();

    bytes memory data = _getSignedSpotDiffData(pk, spotDiffData);
    feed.acceptData(data);
    (, uint confidence) = feed.getResult();
    assertEq(confidence, 1e18);

    spotDiffData.confidence = 0.9e18;
    spotDiffData.timestamp = uint64(block.timestamp - 100);
    data = _getSignedSpotDiffData(pk, spotDiffData);
    feed.acceptData(data);
    (, confidence) = feed.getResult();

    assertEq(confidence, 1e18);
  }

  function testCannotSubmitPriceWithReplacedSigner() public {
    // use a different private key to sign the data but still specify pkOwner as signer
    uint pk2 = 0xBEEF2222;

    ILyraSpotDiffFeed.SpotDiffData memory spotDiffData = _getDefaultSpotDiffData();
    bytes memory data = _getSignedSpotDiffData(pk2, spotDiffData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidSignature.selector);
    feed.acceptData(data);
  }

  function testCannotSetInvalidConfidence() public {
    ILyraSpotDiffFeed.SpotDiffData memory spotDiffData = _getDefaultSpotDiffData();
    spotDiffData.confidence = 1.01e18;
    bytes memory data = _getSignedSpotDiffData(pk, spotDiffData);

    vm.expectRevert(ILyraSpotDiffFeed.LSDF_InvalidConfidence.selector);
    feed.acceptData(data);
  }

  function _getDefaultSpotDiffData() internal view returns (ILyraSpotDiffFeed.SpotDiffData memory) {
    return ILyraSpotDiffFeed.SpotDiffData({
      spotDiff: 10e18,
      confidence: 1e18,
      timestamp: uint64(block.timestamp),
      deadline: block.timestamp + 5,
      signer: pkOwner,
      signature: new bytes(0)
    });
  }

  function _getSignedSpotDiffData(uint privateKey, ILyraSpotDiffFeed.SpotDiffData memory spotDiffData)
    internal
    view
    returns (bytes memory data)
  {
    spotDiffData.signature = _signSpotDiffData(privateKey, spotDiffData);
    return abi.encode(spotDiffData);
  }

  function _signSpotDiffData(uint privateKey, ILyraSpotDiffFeed.SpotDiffData memory spotDiffData)
    internal
    view
    returns (bytes memory)
  {
    bytes32 structHash = feed.hashSpotDiffData(spotDiffData);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ECDSA.toTypedDataHash(domainSeparator, structHash));
    return bytes.concat(r, s, bytes1(v));
  }
}
