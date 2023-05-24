// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "src/feeds/LyraSpotDiffFeed.sol";

/**
 * @dev we deploy actual Account contract in these tests to simplify verification process
 */
contract UNIT_LyraSpotDiffFeed is Test {
  LyraSpotDiffFeed feed;

  bytes32 domainSeparator;

  // signer
  uint private pk;
  address private pkOwner;

  function setUp() public {
    feed = new LyraSpotDiffFeed();
    domainSeparator = feed.domainSeparator();

    // set signer
    pk = 0xBEEF;
    pkOwner = vm.addr(pk);

    vm.warp(block.timestamp + 365 days);
    feed.addSigner(pkOwner, true);
  }

  function testSpotDiff_DomainSeparator() public {
    assertEq(feed.domainSeparator(), domainSeparator);
  }

  function testSpotDiff_CanAddSigner() public {
    address alice = address(0xaaaa);
    feed.addSigner(alice, true);
    assertEq(feed.isSigner(alice), true);
  }

  function testSpotDiff_CanPassInDataAndUpdateSpotDiffFeed() public {
    ILyraSpotDiffFeed.SpotDiffData memory spotDiffData = _getDefaultSpotDiffData();
    bytes memory data = _getSignedSpotDiffData(pk, spotDiffData);

    feed.acceptData(data);

    (int128 spotDiff, uint64 confidence) = feed.getSpotDiff();

    assertEq(spotDiff, -10e18);
    assertEq(confidence, 1e18);
  }

  function testSpotDiff_CantPassInInvalidConfidence() public {
    ILyraSpotDiffFeed.SpotDiffData memory spotDiffData = _getDefaultSpotDiffData();
    spotDiffData.confidence = 1.01e18;
    bytes memory data = _getSignedSpotDiffData(pk, spotDiffData);

    vm.expectRevert(ILyraSpotDiffFeed.LSF_InvalidConfidence.selector);
    feed.acceptData(data);
  }

  function testSpotDiff_CannotUpdateSpotDiffFeedFromInvalidSigner() public {
    // we don't whitelist the pk owner this time
    feed.addSigner(pkOwner, false);

    ILyraSpotDiffFeed.SpotDiffData memory spotDiffData = _getDefaultSpotDiffData();
    bytes memory data = _getSignedSpotDiffData(pk, spotDiffData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidSigner.selector);
    feed.acceptData(data);
  }

  function testSpotDiff_CannotUpdateSpotDiffFeedAfterDeadline() public {
    ILyraSpotDiffFeed.SpotDiffData memory spotDiffData = _getDefaultSpotDiffData();
    bytes memory data = _getSignedSpotDiffData(pk, spotDiffData);

    vm.warp(block.timestamp + 10);

    vm.expectRevert(IBaseLyraFeed.BLF_DataExpired.selector);
    feed.acceptData(data);
  }

  function testSpotDiff_CannotSetSpotInTheFuture() public {
    ILyraSpotDiffFeed.SpotDiffData memory spotDiffData = _getDefaultSpotDiffData();
    spotDiffData.timestamp = uint64(block.timestamp + 1000);

    bytes memory data = _getSignedSpotDiffData(pk, spotDiffData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidTimestamp.selector);
    feed.acceptData(data);
  }

  function testSpotDiff_IgnoreUpdateIfOlderDataIsPushed() public {
    ILyraSpotDiffFeed.SpotDiffData memory spotDiffData = _getDefaultSpotDiffData();
    bytes memory data1 = _getSignedSpotDiffData(pk, spotDiffData);

    feed.acceptData(data1);

    spotDiffData.spotDiff = 100e18;

    // this data has the same timestamp, so it will be ignored
    bytes memory data2 = _getSignedSpotDiffData(pk, spotDiffData);
    feed.acceptData(data2);

    (int128 spotDiff, uint64 confidence) = feed.getSpotDiff();
    assertEq(spotDiff, -10e18);
    assertEq(confidence, 1e18);
  }

  function testSpotDiff_CannotSubmitPriceWithReplacedSigner() public {
    // use a different private key to sign the data but still specify pkOwner as signer
    uint pk2 = 0xBEEF2222;

    // replace pkOwner with random signer address
    ILyraSpotDiffFeed.SpotDiffData memory spotDiffData = _getDefaultSpotDiffData();
    bytes memory data = _getSignedSpotDiffData(pk2, spotDiffData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidSignature.selector);
    feed.acceptData(data);
  }

  function _getDefaultSpotDiffData() internal view returns (ILyraSpotDiffFeed.SpotDiffData memory spotDiffData) {
    return ILyraSpotDiffFeed.SpotDiffData({
      spotDiff: -10e18,
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
