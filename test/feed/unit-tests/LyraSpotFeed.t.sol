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
    feed.addSigner(pkOwner, true);

    bytes memory data = _signPriceData(1000e18, 1.05e18, block.timestamp, block.timestamp + 5, pk, pkOwner);

    feed.sendData(data);

    (uint spot, uint confidence) = feed.getSpot();

    assertEq(spot, 1000e18);
    assertEq(confidence, 1.05e18);
  }

  function testCannotUpdateSpotFeedFromInvalidSigner() public {
    // we didn't whitelist the pk owner this time
    bytes memory data = _signPriceData(1000e18, 1e18, block.timestamp, block.timestamp + 5, pk, pkOwner);

    vm.expectRevert(ILyraSpotFeed.LSF_InvalidSigner.selector);
    feed.sendData(data);
  }

  function testCannotUpdateSpotFeedAfterDeadline() public {
    feed.addSigner(pkOwner, true);
    // we didn't whitelist the pk owner this time
    bytes memory data = _signPriceData(1000e18, 1e18, block.timestamp, block.timestamp + 5, pk, pkOwner);

    vm.warp(block.timestamp + 10);

    vm.expectRevert(ILyraSpotFeed.LSF_DataExpired.selector);
    feed.sendData(data);
  }

  function testCannotSetSpotInTheFuture() public {
    feed.addSigner(pkOwner, true);
    // we didn't whitelist the pk owner this time
    bytes memory data = _signPriceData(1000e18, 1e18, block.timestamp + 1000, block.timestamp + 5, pk, pkOwner);

    vm.expectRevert(ILyraSpotFeed.LSF_InvalidTimestamp.selector);
    feed.sendData(data);
  }

  function testIgnoreUpdateIfOlderDataIsPushed() public {
    feed.addSigner(pkOwner, true);

    bytes memory data1 = _signPriceData(1000e18, 1e18, block.timestamp, block.timestamp + 5, pk, pkOwner);
    feed.sendData(data1);

    // this data is marked as timestamp = block.timestamp -1, will be ignored
    bytes memory data2 = _signPriceData(1100e18, 0.9e18, block.timestamp - 1, block.timestamp + 5, pk, pkOwner);
    feed.sendData(data2);

    (uint spot, uint confidence) = feed.getSpot();
    assertEq(spot, 1000e18);
    assertEq(confidence, 1e18);
  }

  function testCannotSubmitPriceWithReplacedSigner() public {
    feed.addSigner(pkOwner, true);

    // use a different private key to sign the data but still specify pkOwner as signer
    uint pk2 = 0xBEEF2222;

    // replace pkOwner with random signer address
    bytes memory data = _signPriceData(1000e18, 1e18, block.timestamp, block.timestamp + 5, pk2, pkOwner);

    vm.expectRevert(ILyraSpotFeed.LSF_InvalidSignature.selector);
    feed.sendData(data);
  }

  function _signPriceData(
    uint96 price,
    uint96 confidence,
    uint timestamp,
    uint deadline,
    uint privateKey,
    address signer
  ) internal view returns (bytes memory data) {
    ILyraSpotFeed.SpotData memory spotData = ILyraSpotFeed.SpotData({
      deadline: uint64(deadline),
      price: price,
      confidence: confidence,
      timestamp: uint64(timestamp),
      signer: signer,
      signature: new bytes(0)
    });

    bytes memory signature = _signSpotData(privateKey, spotData);
    spotData.signature = signature;

    data = abi.encode(spotData);
  }

  function _signSpotData(uint privateKey, ILyraSpotFeed.SpotData memory spotData) internal view returns (bytes memory) {
    bytes32 structHash = feed.hashSpotData(spotData);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ECDSA.toTypedDataHash(domainSeparator, structHash));
    return bytes.concat(r, s, bytes1(v));
  }
}
