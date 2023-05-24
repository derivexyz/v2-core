// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "src/feeds/LyraVolFeed.sol";
import "../../../src/feeds/LyraForwardFeed.sol";

/**
 * @dev we deploy actual Account contract in these tests to simplify verification process
 */
contract UNIT_LyraForwardFeed is Test {
  LyraForwardFeed feed;

  bytes32 domainSeparator;

  // signer
  uint private pk;
  address private pkOwner;
  uint referenceTime;
  uint64 defaultExpiry;

  function setUp() public {
    feed = new LyraForwardFeed();

    domainSeparator = feed.domainSeparator();

    // set signer
    pk = 0xBEEF;
    pkOwner = vm.addr(pk);

    vm.warp(block.timestamp + 365 days);
    referenceTime = block.timestamp;
    defaultExpiry = uint64(referenceTime + 365 days);

    feed.addSigner(pkOwner, true);
  }

  function testFwdFeed_RevertsWhenFetchingInvalidExpiry() public {
    vm.expectRevert(ILyraForwardFeed.LFF_MissingExpiryData.selector);
    feed.getForwardPrice(defaultExpiry);
  }

  function testFwdFeed_CanPassInDataAndUpdateFwdFeed() public {
    ILyraForwardFeed.ForwardData memory volData = _getDefaultForwardData();
    bytes memory data = _getSignedForwardData(pk, volData);

    feed.acceptData(data);

    (uint fwdPrice, uint confidence) = feed.getForwardPrice(defaultExpiry);
    assertEq(fwdPrice, 1000e18);
    assertEq(confidence, 1e18);
  }

  function testFwdFeed_CannotUpdateFwdFeedFromInvalidSigner() public {
    // we didn't whitelist the pk owner this time
    feed.addSigner(pkOwner, false);

    ILyraForwardFeed.ForwardData memory volData = _getDefaultForwardData();
    bytes memory data = _getSignedForwardData(pk, volData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidSigner.selector);
    feed.acceptData(data);
  }

  function testFwdFeed_CannotUpdateFwdFeedAfterDeadline() public {
    ILyraForwardFeed.ForwardData memory volData = _getDefaultForwardData();
    bytes memory data = _getSignedForwardData(pk, volData);

    vm.warp(block.timestamp + 10);

    vm.expectRevert(IBaseLyraFeed.BLF_DataExpired.selector);
    feed.acceptData(data);
  }

  function testFwdFeed_CannotSetFwdInTheFuture() public {
    ILyraForwardFeed.ForwardData memory volData = _getDefaultForwardData();
    volData.timestamp = uint64(block.timestamp + 1000);
    bytes memory data = _getSignedForwardData(pk, volData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidTimestamp.selector);
    feed.acceptData(data);
  }

  function testFwdFeed_CannotSetFwdPastExpiry() public {
    vm.warp(defaultExpiry + 1);
    ILyraForwardFeed.ForwardData memory volData = _getDefaultForwardData();
    volData.timestamp = uint64(defaultExpiry + 1);
    bytes memory data = _getSignedForwardData(pk, volData);

    vm.expectRevert(ILyraForwardFeed.LFF_InvalidFwdDataTimestamp.selector);
    feed.acceptData(data);
  }

  function testFwdFeed_CanSetSettlementData() public {
    vm.warp(defaultExpiry);
    ILyraForwardFeed.ForwardData memory volData = _getDefaultForwardData();
    volData.timestamp = uint64(defaultExpiry);
    bytes memory data = _getSignedForwardData(pk, volData);
    feed.acceptData(data);

    uint settlementPrice = feed.getSettlementPrice(defaultExpiry);
    assertEq(settlementPrice, 1050e18);
  }

  function testFwdFeed_IgnoreUpdateIfOlderDataIsPushed() public {
    ILyraForwardFeed.ForwardData memory volData = _getDefaultForwardData();

    bytes memory data = _getSignedForwardData(pk, volData);
    feed.acceptData(data);
    (, uint confidence) = feed.getForwardPrice(defaultExpiry);
    assertEq(confidence, 1e18);

    volData.confidence = 0.9e18;
    volData.timestamp = uint64(block.timestamp - 100);
    data = _getSignedForwardData(pk, volData);
    feed.acceptData(data);
    (, confidence) = feed.getForwardPrice(defaultExpiry);

    assertEq(confidence, 1e18);
  }

  function testFwdFeed_SplitForwardFeed() public {
    feed.setHeartbeat(1 days);

    vm.warp(defaultExpiry - 10 minutes);
    ILyraForwardFeed.ForwardData memory volData = _getDefaultForwardData();
    volData.currentSpotAggregate = 1050e18 * uint(defaultExpiry - 10 minutes);
    volData.timestamp = uint64(block.timestamp);
    volData.confidence = 0.99e18;

    bytes memory data = _getSignedForwardData(pk, volData);
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
    vm.expectRevert(ILyraForwardFeed.LFF_InvalidDataTimestampForSettlement.selector);
    feed.getSettlementPrice(defaultExpiry);
  }

  function testFwdFeed_CannotSubmitPriceWithReplacedSigner() public {
    // use a different private key to sign the data but still specify pkOwner as signer
    uint pk2 = 0xBEEF2222;

    ILyraForwardFeed.ForwardData memory volData = _getDefaultForwardData();
    bytes memory data = _getSignedForwardData(pk2, volData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidSignature.selector);
    feed.acceptData(data);
  }

  function _getDefaultForwardData() internal view returns (ILyraForwardFeed.ForwardData memory) {
    return ILyraForwardFeed.ForwardData({
      expiry: defaultExpiry,
      forwardPrice: 1000e18,
      settlementStartAggregate: 1050e18 * uint(defaultExpiry - feed.SETTLEMENT_TWAP_DURATION()),
      currentSpotAggregate: 1050e18 * uint(defaultExpiry),
      confidence: 1e18,
      timestamp: uint64(block.timestamp),
      deadline: block.timestamp + 5,
      signer: pkOwner,
      signature: new bytes(0)
    });
  }

  function _getSignedForwardData(uint privateKey, ILyraForwardFeed.ForwardData memory volData)
    internal
    view
    returns (bytes memory data)
  {
    volData.signature = _signForwardData(privateKey, volData);
    return abi.encode(volData);
  }

  function _signForwardData(uint privateKey, ILyraForwardFeed.ForwardData memory volData)
    internal
    view
    returns (bytes memory)
  {
    bytes32 structHash = feed.hashForwardData(volData);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ECDSA.toTypedDataHash(domainSeparator, structHash));
    return bytes.concat(r, s, bytes1(v));
  }
}
