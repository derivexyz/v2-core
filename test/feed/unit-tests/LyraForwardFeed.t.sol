// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "src/feeds/LyraVolFeed.sol";
import "src/feeds/LyraForwardFeed.sol";
import "../../shared/mocks/MockFeeds.sol";

/**
 * @dev we deploy actual Account contract in these tests to simplify verification process
 */
contract UNIT_LyraForwardFeed is Test {
  MockFeeds mockSpot;
  LyraForwardFeed feed;

  bytes32 domainSeparator;

  // signer
  uint private pk;
  address private pkOwner;
  uint referenceTime;
  uint64 defaultExpiry;

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
    ILyraForwardFeed.ForwardAndSettlementData memory fwdData = _getDefaultForwardData();
    bytes memory data = _getSignedForwardData(pk, fwdData);

    feed.acceptData(data);

    (uint fwdPrice, uint confidence) = feed.getForwardPrice(defaultExpiry);
    assertEq(fwdPrice, 1000e18);
    assertEq(confidence, 1e18);
  }

  function testCannotGetInvalidForwardDiff() public {
    ILyraForwardFeed.ForwardAndSettlementData memory fwdData = _getDefaultForwardData();
    fwdData.fwdSpotDifference = -1000e18;
    feed.acceptData(_getSignedForwardData(pk, fwdData));

    vm.expectRevert("SafeCast: value must be positive");
    feed.getForwardPrice(defaultExpiry);

    vm.warp(block.timestamp + 1);

    // but can return 0
    fwdData.fwdSpotDifference = -990e18;
    fwdData.timestamp += 1;
    feed.acceptData(_getSignedForwardData(pk, fwdData));
    (uint fwdPrice,) = feed.getForwardPrice(defaultExpiry);
    assertEq(fwdPrice, 0);
  }

  function testCannotUpdateFwdFeedFromInvalidSigner() public {
    // we didn't whitelist the pk owner this time
    feed.addSigner(pkOwner, false);

    ILyraForwardFeed.ForwardAndSettlementData memory fwdData = _getDefaultForwardData();
    bytes memory data = _getSignedForwardData(pk, fwdData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidSigner.selector);
    feed.acceptData(data);
  }

  function testCannotUpdateFwdFeedAfterDeadline() public {
    ILyraForwardFeed.ForwardAndSettlementData memory fwdData = _getDefaultForwardData();
    bytes memory data = _getSignedForwardData(pk, fwdData);

    vm.warp(block.timestamp + 10);

    vm.expectRevert(IBaseLyraFeed.BLF_DataExpired.selector);
    feed.acceptData(data);
  }

  function testCannotSetFwdInTheFuture() public {
    ILyraForwardFeed.ForwardAndSettlementData memory fwdData = _getDefaultForwardData();
    fwdData.timestamp = uint64(block.timestamp + 1000);
    bytes memory data = _getSignedForwardData(pk, fwdData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidTimestamp.selector);
    feed.acceptData(data);
  }

  function testCannotSetFwdPastExpiry() public {
    vm.warp(defaultExpiry + 1);
    ILyraForwardFeed.ForwardAndSettlementData memory fwdData = _getDefaultForwardData();
    fwdData.timestamp = uint64(defaultExpiry + 1);
    bytes memory data = _getSignedForwardData(pk, fwdData);

    vm.expectRevert(ILyraForwardFeed.LFF_InvalidFwdDataTimestamp.selector);
    feed.acceptData(data);
  }

  function testCanSetSettlementData() public {
    vm.warp(defaultExpiry);
    ILyraForwardFeed.ForwardAndSettlementData memory fwdData = _getDefaultForwardData();
    fwdData.timestamp = uint64(defaultExpiry);
    bytes memory data = _getSignedForwardData(pk, fwdData);
    feed.acceptData(data);

    (bool settled, uint settlementPrice) = feed.getSettlementPrice(defaultExpiry);
    assertEq(settlementPrice, 1050e18);
    assertTrue(settled);
  }

  function testIgnoreUpdateIfOlderDataIsPushed() public {
    ILyraForwardFeed.ForwardAndSettlementData memory fwdData = _getDefaultForwardData();

    bytes memory data = _getSignedForwardData(pk, fwdData);
    feed.acceptData(data);
    (, uint confidence) = feed.getForwardPrice(defaultExpiry);
    assertEq(confidence, 1e18);

    fwdData.confidence = 0.9e18;
    fwdData.timestamp = uint64(block.timestamp - 100);
    data = _getSignedForwardData(pk, fwdData);
    feed.acceptData(data);
    (, confidence) = feed.getForwardPrice(defaultExpiry);

    assertEq(confidence, 1e18);
  }

  function testSplitForwardFeed() public {
    feed.setHeartbeat(1 days);

    vm.warp(defaultExpiry - 10 minutes);
    ILyraForwardFeed.ForwardAndSettlementData memory fwdData = _getDefaultForwardData();
    fwdData.currentSpotAggregate = 1050e18 * uint(defaultExpiry - 10 minutes);
    fwdData.timestamp = uint64(block.timestamp);
    fwdData.confidence = 0.99e18;

    bytes memory data = _getSignedForwardData(pk, fwdData);
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

    ILyraForwardFeed.ForwardAndSettlementData memory fwdData = _getDefaultForwardData();
    bytes memory data = _getSignedForwardData(pk2, fwdData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidSignature.selector);
    feed.acceptData(data);
  }

  function testCanGetFixedSettlementPriceAfterExpiry() public {
    feed.setHeartbeat(10 minutes);
    // set a forward price entry as settlement data
    vm.warp(defaultExpiry);
    ILyraForwardFeed.ForwardAndSettlementData memory fwdData = _getDefaultForwardData();
    fwdData.timestamp = uint64(defaultExpiry);
    bytes memory data = _getSignedForwardData(pk, fwdData);
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
    ILyraForwardFeed.ForwardAndSettlementData memory fwdData = _getDefaultForwardData();
    fwdData.currentSpotAggregate = 0;
    bytes memory data = _getSignedForwardData(pk, fwdData);

    vm.expectRevert(ILyraForwardFeed.LFF_InvalidSettlementData.selector);
    feed.acceptData(data);
  }

  function testCannotSetInvalidForwardConfidence() public {
    ILyraForwardFeed.ForwardAndSettlementData memory fwdData = _getDefaultForwardData();
    fwdData.confidence = 1.01e18;
    bytes memory data = _getSignedForwardData(pk, fwdData);

    vm.expectRevert(ILyraForwardFeed.LFF_InvalidConfidence.selector);
    feed.acceptData(data);
  }

  function _getDefaultForwardData() internal view returns (ILyraForwardFeed.ForwardAndSettlementData memory) {
    return ILyraForwardFeed.ForwardAndSettlementData({
      expiry: defaultExpiry,
      fwdSpotDifference: 10e18,
      settlementStartAggregate: 1050e18 * uint(defaultExpiry - feed.SETTLEMENT_TWAP_DURATION()),
      currentSpotAggregate: 1050e18 * uint(defaultExpiry),
      confidence: 1e18,
      timestamp: uint64(block.timestamp),
      deadline: block.timestamp + 5,
      signer: pkOwner,
      signature: new bytes(0)
    });
  }

  function _getSignedForwardData(uint privateKey, ILyraForwardFeed.ForwardAndSettlementData memory fwdData)
    internal
    view
    returns (bytes memory data)
  {
    fwdData.signature = _signForwardData(privateKey, fwdData);
    return abi.encode(fwdData);
  }

  function _signForwardData(uint privateKey, ILyraForwardFeed.ForwardAndSettlementData memory fwdData)
    internal
    view
    returns (bytes memory)
  {
    bytes32 structHash = feed.hashForwardData(fwdData);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ECDSA.toTypedDataHash(domainSeparator, structHash));
    return bytes.concat(r, s, bytes1(v));
  }
}
