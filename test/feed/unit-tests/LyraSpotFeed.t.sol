// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "src/feeds/LyraSpotFeed.sol";

/**
 * @dev we deploy actual Account contract in these tests to simplify verification process
 */
contract UNIT_LyraSpotFeed is Test {
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

  function testDomainSeparator() public {
    assertEq(feed.domainSeparator(), domainSeparator);
  }

  function testCanAddSigner() public {
    address alice = address(0xaaaa);
    feed.addSigner(alice, true);
    assertEq(feed.isSigner(alice), true);
  }

  function testCanPassInDataAndUpdateSpotFeed() public {
    ILyraSpotFeed.SpotData memory spotData = _getDefaultSpotData();
    bytes memory data = _getSignedSpotData(pk, spotData);

    feed.acceptData(data);

    (uint spot, uint confidence) = feed.getSpot();

    assertEq(spot, 1000e18);
    assertEq(confidence, 1e18);
  }

  function testCantPassInInvalidConfidence() public {
    ILyraSpotFeed.SpotData memory spotData = _getDefaultSpotData();
    spotData.confidence = 1.01e18;
    bytes memory data = _getSignedSpotData(pk, spotData);

    vm.expectRevert(ILyraSpotFeed.LSF_InvalidConfidence.selector);
    feed.acceptData(data);
  }

  function testCannotUpdateSpotFeedFromInvalidSigner() public {
    // we don't whitelist the pk owner this time
    feed.addSigner(pkOwner, false);

    ILyraSpotFeed.SpotData memory spotData = _getDefaultSpotData();
    bytes memory data = _getSignedSpotData(pk, spotData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidSigner.selector);
    feed.acceptData(data);
  }

  function testCannotUpdateSpotFeedAfterDeadline() public {
    ILyraSpotFeed.SpotData memory spotData = _getDefaultSpotData();
    bytes memory data = _getSignedSpotData(pk, spotData);

    vm.warp(block.timestamp + 10);

    vm.expectRevert(IBaseLyraFeed.BLF_DataExpired.selector);
    feed.acceptData(data);
  }

  function testCannotSetSpotInTheFuture() public {
    ILyraSpotFeed.SpotData memory spotData = _getDefaultSpotData();
    spotData.timestamp = uint64(block.timestamp + 1000);

    bytes memory data = _getSignedSpotData(pk, spotData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidTimestamp.selector);
    feed.acceptData(data);
  }

  function testIgnoreUpdateIfOlderDataIsPushed() public {
    ILyraSpotFeed.SpotData memory spotData = _getDefaultSpotData();
    bytes memory data1 = _getSignedSpotData(pk, spotData);

    feed.acceptData(data1);

    spotData.price = 1100e18;

    // this data has the same timestamp, so it will be ignored
    bytes memory data2 = _getSignedSpotData(pk, spotData);
    feed.acceptData(data2);

    (uint spot, uint confidence) = feed.getSpot();
    assertEq(spot, 1000e18);
    assertEq(confidence, 1e18);
  }

  function testCannotSubmitPriceWithReplacedSigner() public {
    // use a different private key to sign the data but still specify pkOwner as signer
    uint pk2 = 0xBEEF2222;

    // replace pkOwner with random signer address
    ILyraSpotFeed.SpotData memory spotData = _getDefaultSpotData();
    bytes memory data = _getSignedSpotData(pk2, spotData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidSignature.selector);
    feed.acceptData(data);
  }

  function _getDefaultSpotData() internal view returns (ILyraSpotFeed.SpotData memory spotData) {
    return ILyraSpotFeed.SpotData({
      price: 1000e18,
      confidence: 1e18,
      timestamp: uint64(block.timestamp),
      deadline: block.timestamp + 5,
      signer: pkOwner,
      signature: new bytes(0)
    });
  }

  function _getSignedSpotData(uint privateKey, ILyraSpotFeed.SpotData memory spotData)
    internal
    view
    returns (bytes memory data)
  {
    spotData.signature = _signSpotData(privateKey, spotData);
    return abi.encode(spotData);
  }

  function _signSpotData(uint privateKey, ILyraSpotFeed.SpotData memory spotData) internal view returns (bytes memory) {
    bytes32 structHash = feed.hashSpotData(spotData);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ECDSA.toTypedDataHash(domainSeparator, structHash));
    return bytes.concat(r, s, bytes1(v));
  }
}
