// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "src/feeds/LyraVolFeed.sol";

/**
 * @dev we deploy actual Account contract in these tests to simplify verification process
 */
contract UNIT_LyraVolFeed is Test {
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

  function testDomainSeparator() public {
    assertEq(feed.domainSeparator(), domainSeparator);
  }

  function testCanAddSigner() public {
    address alice = address(0xaaaa);
    feed.addSigner(alice, true);
    assertEq(feed.isSigner(alice), true);
  }

  function testRevertsWhenFetchingInvalidExpiry() public {
    vm.expectRevert(ILyraVolFeed.LVF_MissingExpiryData.selector);
    feed.getVol(uint128(uint(1500e18)), defaultExpiry);
  }

  function testCanPassInDataAndUpdateVolFeed() public {
    ILyraVolFeed.VolData memory volData = _getDefaultVolData();
    bytes memory data = _getSignedVolData(pk, volData);

    feed.acceptData(data);

    (uint vol, uint confidence) = feed.getVol(uint128(uint(1500e18)), defaultExpiry);
    console2.log("1500 vol", vol);
    assertApproxEqAbs(vol, 1.1728e18, 0.0001e18);
    assertEq(confidence, 1e18);
  }

  function testCannotUpdateVolFeedFromInvalidSigner() public {
    // we didn't whitelist the pk owner this time
    feed.addSigner(pkOwner, false);

    ILyraVolFeed.VolData memory volData = _getDefaultVolData();
    bytes memory data = _getSignedVolData(pk, volData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidSigner.selector);
    feed.acceptData(data);
  }

  function testCannotUpdateVolFeedAfterDeadline() public {
    ILyraVolFeed.VolData memory volData = _getDefaultVolData();
    bytes memory data = _getSignedVolData(pk, volData);

    vm.warp(block.timestamp + 10);

    vm.expectRevert(IBaseLyraFeed.BLF_DataExpired.selector);
    feed.acceptData(data);
  }

  function testCannotSetVolInTheFuture() public {
    ILyraVolFeed.VolData memory volData = _getDefaultVolData();
    volData.timestamp = uint64(block.timestamp + 1000);
    bytes memory data = _getSignedVolData(pk, volData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidTimestamp.selector);
    feed.acceptData(data);
  }

  function testIgnoreUpdateIfOlderDataIsPushed() public {
    ILyraVolFeed.VolData memory volData = _getDefaultVolData();

    bytes memory data = _getSignedVolData(pk, volData);
    feed.acceptData(data);
    (, uint confidence) = feed.getVol(uint128(uint(1500e18)), defaultExpiry);
    assertEq(confidence, 1e18);

    volData.confidence = 0.9e18;
    volData.timestamp = uint64(block.timestamp - 100);
    data = _getSignedVolData(pk, volData);
    feed.acceptData(data);
    (, confidence) = feed.getVol(uint128(uint(1500e18)), defaultExpiry);

    assertEq(confidence, 1e18);
  }

  function testCannotSubmitPriceWithReplacedSigner() public {
    // use a different private key to sign the data but still specify pkOwner as signer
    uint pk2 = 0xBEEF2222;

    ILyraVolFeed.VolData memory volData = _getDefaultVolData();
    bytes memory data = _getSignedVolData(pk2, volData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidSignature.selector);
    feed.acceptData(data);
  }

  function _getDefaultVolData() internal view returns (ILyraVolFeed.VolData memory) {
    // example data: a = 1, b = 1.5, sig = 0.05, rho = -0.1, m = -0.05
    return ILyraVolFeed.VolData({
      expiry: defaultExpiry,
      SVI_a: 1e18,
      SVI_b: 1.5e18,
      SVI_rho: -0.1e18,
      SVI_m: -0.05e18,
      SVI_sigma: 0.05e18,
      SVI_fwd: 1200e18,
      confidence: 1e18,
      timestamp: uint64(block.timestamp),
      deadline: block.timestamp + 5,
      signer: pkOwner,
      signature: new bytes(0)
    });
  }

  function _getSignedVolData(uint privateKey, ILyraVolFeed.VolData memory volData)
    internal
    view
    returns (bytes memory data)
  {
    volData.signature = _signVolData(privateKey, volData);
    return abi.encode(volData);
  }

  function _signVolData(uint privateKey, ILyraVolFeed.VolData memory volData) internal view returns (bytes memory) {
    bytes32 structHash = feed.hashVolData(volData);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ECDSA.toTypedDataHash(domainSeparator, structHash));
    return bytes.concat(r, s, bytes1(v));
  }
}
