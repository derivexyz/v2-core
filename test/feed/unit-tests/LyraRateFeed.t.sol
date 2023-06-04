// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "src/feeds/LyraRateFeed.sol";

contract UNIT_LyraRateFeed is Test {
  LyraRateFeed feed;

  bytes32 domainSeparator;

  // signer
  uint private pk;
  address private pkOwner;

  uint referenceTime;
  uint64 defaultExpiry;

  function setUp() public {
    feed = new LyraRateFeed();
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

  function testCanPassInDataAndUpdateRateFeed() public {
    ILyraRateFeed.RateData memory rateData = _getDefaultRateData();
    feed.acceptData(_getSignedRateData(pk, rateData));

    (int rate, uint confidence) = feed.getInterestRate(defaultExpiry);

    assertEq(rate, int(-0.1e18));
    assertEq(confidence, 1e18);
  }

  function testCantPassInInvalidConfidence() public {
    ILyraRateFeed.RateData memory rateData = _getDefaultRateData();
    rateData.confidence = 1.01e18;
    bytes memory data = _getSignedRateData(pk, rateData);

    vm.expectRevert(ILyraRateFeed.LSF_InvalidConfidence.selector);
    feed.acceptData(data);
  }

  function testCannotUpdateRateFeedFromInvalidSigner() public {
    // we don't whitelist the pk owner this time
    feed.addSigner(pkOwner, false);

    ILyraRateFeed.RateData memory rateData = _getDefaultRateData();
    bytes memory data = _getSignedRateData(pk, rateData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidSigner.selector);
    feed.acceptData(data);
  }

  function testCannotUpdateRateFeedAfterDeadline() public {
    ILyraRateFeed.RateData memory rateData = _getDefaultRateData();
    bytes memory data = _getSignedRateData(pk, rateData);

    vm.warp(block.timestamp + 10);

    vm.expectRevert(IBaseLyraFeed.BLF_DataExpired.selector);
    feed.acceptData(data);
  }

  function testCannotSetRateInTheFuture() public {
    ILyraRateFeed.RateData memory rateData = _getDefaultRateData();
    rateData.timestamp = uint64(block.timestamp + 1000);

    bytes memory data = _getSignedRateData(pk, rateData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidTimestamp.selector);
    feed.acceptData(data);
  }

  function testIgnoreUpdateIfOlderDataIsPushed() public {
    ILyraRateFeed.RateData memory rateData = _getDefaultRateData();
    feed.acceptData(_getSignedRateData(pk, rateData));

    // this data has the same timestamp, so it will be ignored
    rateData.rate = 0.1e18;
    feed.acceptData(_getSignedRateData(pk, rateData));

    (int rate, uint confidence) = feed.getInterestRate(defaultExpiry);
    assertEq(rate, -0.1e18);
    assertEq(confidence, 1e18);
  }

  function testCannotSubmitPriceWithReplacedSigner() public {
    // use a different private key to sign the data but still specify pkOwner as signer
    uint pk2 = 0xBEEF2222;

    // replace pkOwner with random signer address
    ILyraRateFeed.RateData memory rateData = _getDefaultRateData();
    bytes memory data = _getSignedRateData(pk2, rateData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidSignature.selector);
    feed.acceptData(data);
  }

  function _getDefaultRateData() internal view returns (ILyraRateFeed.RateData memory rateData) {
    return ILyraRateFeed.RateData({
      expiry: defaultExpiry,
      rate: -0.1e18,
      confidence: 1e18,
      timestamp: uint64(block.timestamp),
      deadline: block.timestamp + 5,
      signer: pkOwner,
      signature: new bytes(0)
    });
  }

  function _getSignedRateData(uint privateKey, ILyraRateFeed.RateData memory rateData)
    internal
    view
    returns (bytes memory data)
  {
    rateData.signature = _signRateData(privateKey, rateData);
    return abi.encode(rateData);
  }

  function _signRateData(uint privateKey, ILyraRateFeed.RateData memory rateData) internal view returns (bytes memory) {
    bytes32 structHash = feed.hashRateData(rateData);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ECDSA.toTypedDataHash(domainSeparator, structHash));
    return bytes.concat(r, s, bytes1(v));
  }
}
