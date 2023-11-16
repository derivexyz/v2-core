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
  uint private pk2;
  address private pkOwner2;

  function setUp() public {
    feed = new LyraSpotFeed();
    domainSeparator = feed.domainSeparator();

    // set signer
    pk = 0xBEEF;
    pkOwner = vm.addr(pk);

    pk2 = 0xc00c;
    pkOwner2 = vm.addr(pk2);

    vm.warp(block.timestamp + 365 days);
    feed.addSigner(pkOwner, true);
    feed.addSigner(pkOwner2, true);
  }

  // shared function in BaseLyraFeed

  function testDomainSeparator() public {
    assertEq(feed.domainSeparator(), domainSeparator);
  }

  function testCanAddSigner() public {
    address alice = address(0xaaaa);
    feed.addSigner(alice, true);
    assertEq(feed.isSigner(alice), true);
  }

  function testCanSetSignerRequired() public {
    feed.setRequiredSigners(3);
    assertEq(feed.requiredSigners(), 3);
  }

  function testCannotSetSignerRequiredToZero() public {
    vm.expectRevert(IBaseLyraFeed.BLF_InvalidRequiredSigners.selector);
    feed.setRequiredSigners(0);
  }

  function testCanUseMultipleSigners() public {
    feed.setRequiredSigners(2);

    IBaseLyraFeed.FeedData memory spotData = _getDefaultSpotDataMultipleSigners(2);
    bytes32 structHash = hashFeedData(feed, spotData);

    // signed by pk
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, ECDSA.toTypedDataHash(feed.domainSeparator(), structHash));
    spotData.signatures[0] = bytes.concat(r, s, bytes1(v));
    spotData.signers[0] = pkOwner;
    // signed by pk2
    (v, r, s) = vm.sign(pk2, ECDSA.toTypedDataHash(feed.domainSeparator(), structHash));
    spotData.signatures[1] = bytes.concat(r, s, bytes1(v));
    spotData.signers[1] = pkOwner2;

    bytes memory data = abi.encode(spotData);
    feed.acceptData(data);

    (uint spot, uint confidence) = feed.getSpot();
    assertEq(spot, 1000e18);
    assertEq(confidence, 1e18);
  }

  function testCannotUpdateWithNoSigners() public {
    IBaseLyraFeed.FeedData memory spotData = _getDefaultSpotDataMultipleSigners(0);
    bytes memory data = abi.encode(spotData);

    vm.expectRevert(IBaseLyraFeed.BLF_NotEnoughSigners.selector);
    feed.acceptData(data);
  }

  function testCannotUpdateIfNotEnoughSigners() public {
    feed.setRequiredSigners(2);

    IBaseLyraFeed.FeedData memory spotData = _getDefaultSpotDataMultipleSigners(1);
    bytes32 structHash = hashFeedData(feed, spotData);

    // signed by pk
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, ECDSA.toTypedDataHash(feed.domainSeparator(), structHash));
    spotData.signatures[0] = bytes.concat(r, s, bytes1(v));
    spotData.signers[0] = pkOwner;

    bytes memory data = abi.encode(spotData);

    vm.expectRevert(IBaseLyraFeed.BLF_NotEnoughSigners.selector);
    feed.acceptData(data);
  }

  function testCannotUseSameSigner() public {
    feed.setRequiredSigners(2);

    IBaseLyraFeed.FeedData memory spotData = _getDefaultSpotDataMultipleSigners(2);
    bytes32 structHash = hashFeedData(feed, spotData);

    // signatures[0]: signed by pk
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, ECDSA.toTypedDataHash(feed.domainSeparator(), structHash));
    spotData.signatures[0] = bytes.concat(r, s, bytes1(v));
    spotData.signers[0] = pkOwner;
    // signatures[1]: signed by pk
    (v, r, s) = vm.sign(pk, ECDSA.toTypedDataHash(feed.domainSeparator(), structHash));
    spotData.signatures[1] = bytes.concat(r, s, bytes1(v));
    spotData.signers[1] = pkOwner;

    bytes memory data = abi.encode(spotData);
    vm.expectRevert(IBaseLyraFeed.BLF_DuplicatedSigner.selector);
    feed.acceptData(data);
  }

  function testCannotSubmitMismatchedData() public {
    IBaseLyraFeed.FeedData memory spotData = _getDefaultSpotDataMultipleSigners(3);
    spotData.signatures = new bytes[](0);
    spotData.signers[0] = pkOwner;
    bytes memory data = abi.encode(spotData);

    vm.expectRevert(IBaseLyraFeed.BLF_SignatureSignersLengthMismatch.selector);
    feed.acceptData(data);
  }

  function testCannotUseSameSigner2() public {
    feed.setRequiredSigners(3);

    IBaseLyraFeed.FeedData memory spotData = _getDefaultSpotDataMultipleSigners(3);
    bytes32 structHash = hashFeedData(feed, spotData);

    // signed by pk
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, ECDSA.toTypedDataHash(feed.domainSeparator(), structHash));
    spotData.signatures[0] = bytes.concat(r, s, bytes1(v));
    spotData.signers[0] = pkOwner;
    // signed by pk2 (valid)
    (v, r, s) = vm.sign(pk2, ECDSA.toTypedDataHash(feed.domainSeparator(), structHash));
    spotData.signatures[1] = bytes.concat(r, s, bytes1(v));
    spotData.signers[1] = pkOwner2;
    // signatures[2]: signed by pk again
    (v, r, s) = vm.sign(pk, ECDSA.toTypedDataHash(feed.domainSeparator(), structHash));
    spotData.signatures[2] = bytes.concat(r, s, bytes1(v));
    spotData.signers[2] = pkOwner;

    bytes memory data = abi.encode(spotData);
    vm.expectRevert(IBaseLyraFeed.BLF_DuplicatedSigner.selector);
    feed.acceptData(data);
  }

  function testCanHashFeedData() public view {
    IBaseLyraFeed.FeedData memory spotData = _getDefaultSpotDataMultipleSigners(3);
    feed.hashFeedData(spotData);
  }

  function _getDefaultSpotDataMultipleSigners(uint numSigners) internal view returns (IBaseLyraFeed.FeedData memory) {
    uint96 price = 1000e18;
    uint64 confidence = 1e18;
    bytes memory spotData = abi.encode(price, confidence);

    return IBaseLyraFeed.FeedData({
      data: spotData,
      timestamp: uint64(block.timestamp),
      deadline: block.timestamp + 5,
      signers: new address[](numSigners),
      signatures: new bytes[](numSigners)
    });
  }
}
