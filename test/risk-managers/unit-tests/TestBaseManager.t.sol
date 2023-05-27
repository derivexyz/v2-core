// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "openzeppelin/token/ERC20/IERC20.sol";
import "lyra-utils/encoding/OptionEncoding.sol";

import {IManager} from "src/interfaces/IManager.sol";
import "src/interfaces/ICashAsset.sol";
import "src/interfaces/IOption.sol";

import "src/SubAccounts.sol";
import "src/risk-managers/BaseManager.sol";

import "src/feeds/AllowList.sol";

import "../../shared/mocks/MockAsset.sol";
import "../../shared/mocks/MockERC20.sol";
import "../../shared/mocks/MockFeeds.sol";
import "../../shared/mocks/MockOption.sol";
import "../../auction/mocks/MockCashAsset.sol";
import "../../shared/mocks/MockPerp.sol";

contract BaseManagerTester is BaseManager {
  IOption public immutable option;
  IPerpAsset public immutable perp;
  IForwardFeed public immutable forwardFeed;
  ISpotFeed public immutable spotFeed;
  ISettlementFeed public immutable settlementFeed;

  constructor(
    ISubAccounts subAccounts_,
    IForwardFeed forwardFeed_,
    ISettlementFeed settlementFeed_,
    ISpotFeed spotFeed_,
    ICashAsset cash_,
    IOption option_,
    IPerpAsset perp_,
    IDutchAuction auction_
  ) BaseManager(subAccounts_, cash_, auction_) {
    option = option_;
    perp = perp_;
    forwardFeed = forwardFeed_;
    settlementFeed = settlementFeed_;
    spotFeed = spotFeed_;
  }

  function symmetricManagerAdjustment(uint from, uint to, IAsset asset, uint96 subId, int amount) external {
    _symmetricManagerAdjustment(from, to, asset, subId, amount);
  }

  function getOptionOIFee(IOITracking asset, int delta, uint subId, uint tradeId) external view returns (uint fee) {
    fee = _getOptionOIFee(asset, forwardFeed, delta, subId, tradeId);
  }

  function getPerpOIFee(IOITracking asset, int delta, uint tradeId) external view returns (uint fee) {
    fee = _getPerpOIFee(asset, spotFeed, delta, tradeId);
  }

  function checkAssetCap(IOITracking asset) external view {
    return _checkAssetCap(asset);
  }

  function settleOptions(uint accountId) external {
    _settleAccountOptions(option, accountId);
  }

  function handleAdjustment(
    uint, /*accountId*/
    uint, /*tradeId*/
    address,
    ISubAccounts.AssetDelta[] calldata, /*assetDeltas*/
    bytes memory
  ) public {}

  function getMargin(uint, bool) external view returns (int) {}

  function getMarginAndMarkToMarket(uint accountId, bool isInitial, uint scenarioId) external view returns (int, int) {}
}

contract UNIT_TestAbstractBaseManager is Test {
  SubAccounts subAccounts;
  BaseManagerTester tester;

  MockAsset mockAsset;
  MockFeeds feed;
  MockERC20 usdc;
  MockOption option;
  MockCash cash;
  MockPerp perp;

  address alice = address(0xaa);
  address bob = address(0xb0ba);

  uint aliceAcc;
  uint bobAcc;
  uint feeRecipientAcc;

  uint expiry;

  address mockAuction = address(0xdd);

  function setUp() public {
    subAccounts = new SubAccounts("Lyra Accounts", "LyraAccount");

    feed = new MockFeeds();
    usdc = new MockERC20("USDC", "USDC");
    option = new MockOption(subAccounts);
    perp = new MockPerp(subAccounts);
    cash = new MockCash(usdc, subAccounts);

    tester = new BaseManagerTester(subAccounts, feed, feed, feed, cash, option, perp, IDutchAuction(mockAuction));

    mockAsset = new MockAsset(usdc, subAccounts, true);

    aliceAcc = subAccounts.createAccount(alice, IManager(address(tester)));

    bobAcc = subAccounts.createAccount(bob, IManager(address(tester)));

    feeRecipientAcc = subAccounts.createAccount(address(this), IManager(address(tester)));

    tester.setFeeRecipient(feeRecipientAcc);

    expiry = block.timestamp + 7 days;

    usdc.mint(address(this), 2000_000e18);
    usdc.approve(address(mockAsset), 2000_000e18);
    usdc.approve(address(cash), 2000_000e18);
  }

  function testTransferWithoutMarginPositiveAmount() public {
    int amount = 5000 * 1e18;
    tester.symmetricManagerAdjustment(aliceAcc, bobAcc, mockAsset, 0, amount);

    assertEq(subAccounts.getBalance(aliceAcc, mockAsset, 0), -amount);
    assertEq(subAccounts.getBalance(bobAcc, mockAsset, 0), amount);
  }

  function testTransferWithoutMarginNegativeAmount() public {
    int amount = -5000 * 1e18;
    tester.symmetricManagerAdjustment(aliceAcc, bobAcc, mockAsset, 0, amount);

    assertEq(subAccounts.getBalance(aliceAcc, mockAsset, 0), -amount);
    assertEq(subAccounts.getBalance(bobAcc, mockAsset, 0), amount);
  }

  /* ------------------------- *
   *    Test OI fee getters    *
   * ------------------------- **/

  function testOptionFeeIfOIIncrease() public {
    tester.setOIFeeRateBPS(0.001e18);
    feed.setForwardPrice(expiry, 2000e18, 1e18);

    uint96 subId = OptionEncoding.toSubId(expiry, 2500e18, true);
    uint tradeId = 5;

    // OI increase
    option.setMockedOISnapshotBeforeTrade(subId, tradeId, 0);
    option.setMockedOI(subId, 100e18);

    // fee = 1 * 0.1% * 2000;
    assertEq(tester.getOptionOIFee(option, 1e18, subId, tradeId), 2e18);
  }

  function testNoOptionFeeIfOIDecrease() public {
    tester.setOIFeeRateBPS(0.001e18);
    feed.setForwardPrice(expiry, 2000e18, 1e18);

    uint96 subId = OptionEncoding.toSubId(expiry, 2500e18, true);
    uint tradeId = 5;

    // OI increase
    option.setMockedOISnapshotBeforeTrade(subId, tradeId, 100e18);
    option.setMockedOI(subId, 0);

    assertEq(tester.getOptionOIFee(option, 1e18, subId, tradeId), 0);
  }

  // OI Fee on Perps

  function testPerpFeeIfOIIncrease() public {
    tester.setOIFeeRateBPS(0.001e18);

    feed.setSpot(5000e18, 1e18);
    uint tradeId = 5;

    // OI increase
    perp.setMockedOISnapshotBeforeTrade(0, tradeId, 0);
    perp.setMockedOI(0, 100e18);

    // fee = 1 * 0.1% * 5000;
    assertEq(tester.getPerpOIFee(perp, 1e18, tradeId), 5e18);
  }

  function testNoPerpFeeIfOIDecrease() public {
    tester.setOIFeeRateBPS(0.001e18);
    feed.setSpot(6000e18, 1e18);
    uint tradeId = 5;

    // OI increase
    perp.setMockedOISnapshotBeforeTrade(0, tradeId, 100e18);
    perp.setMockedOI(0, 0);

    assertEq(tester.getPerpOIFee(perp, 1e18, tradeId), 0);
  }

  // ================================
  //            Test Caps
  // ================================

  function testExceedCapCheck() public {
    // mock exceed cap
    perp.setTotalPosition(tester, 100e18);
    perp.setTotalPositionCap(tester, 5e18);

    vm.expectRevert(IBaseManager.BM_AssetCapExceeded.selector);
    tester.checkAssetCap(perp);
  }

  function testAssetCapSet() public {
    perp.setTotalPosition(tester, 100e18);
    tester.checkAssetCap(perp); // no revert

    perp.setTotalPositionCap(tester, 100e18);
    tester.checkAssetCap(perp); // no revert
  }

  // ================================
  //            Settlement
  // ================================

  function testSettlementNetPositive() external {
    (uint callId, uint putId) = _openDefaultPositions();

    // mock settlement value
    option.setMockedSubIdSettled(callId, true);
    option.setMockedSubIdSettled(putId, true);
    option.setMockedTotalSettlementValue(callId, -500e18);
    option.setMockedTotalSettlementValue(putId, 1000e18);

    tester.settleOptions(aliceAcc);

    assertEq(subAccounts.getBalance(aliceAcc, option, callId), 0);
    assertEq(subAccounts.getBalance(aliceAcc, option, putId), 0);

    // cash increase
    assertEq(subAccounts.getBalance(aliceAcc, cash, 0), 500e18);
  }

  function testSettlementNetNegative() external {
    (uint callId, uint putId) = _openDefaultPositions();

    // mock settlement value
    option.setMockedSubIdSettled(callId, true);
    option.setMockedSubIdSettled(putId, true);
    option.setMockedTotalSettlementValue(callId, -1500e18);
    option.setMockedTotalSettlementValue(putId, 200e18);

    tester.settleOptions(aliceAcc);

    assertEq(subAccounts.getBalance(aliceAcc, option, callId), 0);
    assertEq(subAccounts.getBalance(aliceAcc, option, putId), 0);

    // cash increase
    assertEq(subAccounts.getBalance(aliceAcc, cash, 0), -1300e18);
  }

  function testSettleOnUnsettledAsset() external {
    (uint callId, uint putId) = _openDefaultPositions();

    int callBalanceBefore = subAccounts.getBalance(aliceAcc, option, callId);
    int putBalanceBefore = subAccounts.getBalance(aliceAcc, option, putId);

    // mock settlement value: settled still remain false
    option.setMockedTotalSettlementValue(callId, -500e18);
    option.setMockedTotalSettlementValue(putId, 1000e18);

    tester.settleOptions(aliceAcc);

    assertEq(subAccounts.getBalance(aliceAcc, option, callId), callBalanceBefore);
    assertEq(subAccounts.getBalance(aliceAcc, option, putId), putBalanceBefore);
    // cash increase
    assertEq(subAccounts.getBalance(aliceAcc, cash, 0), 0);
  }

  function testSettleCashInterest() external {
    tester.settleInterest(aliceAcc);
  }

  // ------------------------
  //      Execute Bids
  // ------------------------

  function testCannotExecuteBidFromNonLiquidation() external {
    vm.expectRevert(IBaseManager.BM_OnlyLiquidationModule.selector);
    tester.executeBid(aliceAcc, bobAcc, 0.5e18, 0);
  }

  function testCannotExecuteInvalidBid() external {
    vm.startPrank(mockAuction);
    vm.expectRevert(IBaseManager.BM_InvalidBidPortion.selector);
    tester.executeBid(aliceAcc, bobAcc, 1.2e18, 0);
    vm.stopPrank();
  }

  function testCannotExecuteBidIfLiquidatorHoldsNonCash() external {
    vm.startPrank(mockAuction);

    tester.symmetricManagerAdjustment(aliceAcc, bobAcc, mockAsset, 0, 1e18);
    vm.expectRevert(IBaseManager.BM_LiquidatorCanOnlyHaveCash.selector);
    tester.executeBid(aliceAcc, bobAcc, 0.5e18, 0);

    vm.stopPrank();
  }

  function testCannotExecuteBidIfHoldTooManyAssets() external {
    vm.startPrank(mockAuction);

    // balance[0] is cash
    tester.symmetricManagerAdjustment(aliceAcc, bobAcc, cash, 0, 1e18);
    // balance[1] is not cash
    tester.symmetricManagerAdjustment(aliceAcc, bobAcc, mockAsset, 0, 1e18);
    vm.expectRevert(IBaseManager.BM_LiquidatorCanOnlyHaveCash.selector);
    tester.executeBid(aliceAcc, bobAcc, 0.5e18, 0);

    vm.stopPrank();
  }

  function testExecuteBidFromBidderWithNoCash() external {
    // under some edge cases, people should be able to just "receive" the portfolio without paying anything
    // for example at the end of insolvent auction, anyone can use a empty account to receive the portfolio + initial margin

    // alice' portfolio
    mockAsset.deposit(aliceAcc, 0, 1e18);
    mockAsset.deposit(aliceAcc, 1, 1e18);

    vm.startPrank(mockAuction);
    tester.executeBid(aliceAcc, bobAcc, 1e18, 0);

    assertEq(subAccounts.getBalance(aliceAcc, mockAsset, 0), 0);
    assertEq(subAccounts.getBalance(bobAcc, mockAsset, 0), 1e18);

    assertEq(subAccounts.getBalance(aliceAcc, mockAsset, 1), 0);
    assertEq(subAccounts.getBalance(bobAcc, mockAsset, 1), 1e18);

    vm.stopPrank();
  }

  function testExecuteBidPartial() external {
    uint amount = 200e18;
    // alice' portfolio: 200 mockAsset
    mockAsset.deposit(aliceAcc, 0, amount);

    // bob's portfolio 100e18
    cash.deposit(bobAcc, 0, 100e18);
    uint bid = 30e18;

    vm.startPrank(mockAuction);

    // liquidate 80%
    tester.executeBid(aliceAcc, bobAcc, 0.8e18, bid);

    assertEq(subAccounts.getBalance(aliceAcc, mockAsset, 0), 40e18);
    assertEq(subAccounts.getBalance(aliceAcc, cash, 0), int(bid));

    assertEq(subAccounts.getBalance(bobAcc, mockAsset, 0), 160e18);
    assertEq(subAccounts.getBalance(bobAcc, cash, 0), 70e18); // cas

    vm.stopPrank();
  }

  // -----------------------------
  //      Pay liquidation fee
  // -----------------------------

  function testCannotExecutePayFeeFromNonLiquidation() external {
    vm.expectRevert(IBaseManager.BM_OnlyLiquidationModule.selector);
    tester.payLiquidationFee(aliceAcc, bobAcc, 1e18);
  }

  function testCanPayLiquidationFee() external {
    // balances
    uint amount = 200e18;
    // alice' portfolio: 200 mockAsset
    mockAsset.deposit(aliceAcc, 0, amount);
    cash.deposit(aliceAcc, 0, amount);

    vm.startPrank(mockAuction);
    tester.payLiquidationFee(aliceAcc, bobAcc, 1e18);

    assertEq(subAccounts.getBalance(aliceAcc, mockAsset, 0), int(amount));
    assertEq(subAccounts.getBalance(aliceAcc, cash, 0), 199e18);
  }

  // ------------------------
  //      force withdraw
  // ------------------------

  function testCanSetAllowlist() public {
    AllowList allowlist = new AllowList();
    tester.setAllowList(allowlist);

    assertEq(address(tester.allowList()), address(allowlist));
  }

  function testCannotForceWithdrawIFOnAllowlist() public {
    vm.expectRevert(IBaseManager.BM_OnlyBlockedAccounts.selector);
    tester.forceWithdrawAccount(aliceAcc);
  }

  function testCanForceWithdrawCashAccounts() public {
    AllowList allowlist = new AllowList();
    tester.setAllowList(allowlist);
    allowlist.setAllowListEnabled(true);

    // alice with -$1000 cash, bob with +1000 cash
    tester.symmetricManagerAdjustment(aliceAcc, bobAcc, cash, 0, 1000e18);

    tester.forceWithdrawAccount(aliceAcc);
  }

  function testCanForceWithdrawNonCashAccount() public {
    AllowList allowlist = new AllowList();
    tester.setAllowList(allowlist);
    allowlist.setAllowListEnabled(true);

    // alice has no asset
    vm.expectRevert(IBaseManager.BM_InvalidForceWithdrawAccountState.selector);
    tester.forceWithdrawAccount(aliceAcc);

    // alice with -$1000 mockAsset
    tester.symmetricManagerAdjustment(aliceAcc, bobAcc, mockAsset, 0, 1000e18);

    vm.expectRevert(IBaseManager.BM_InvalidForceWithdrawAccountState.selector);
    tester.forceWithdrawAccount(aliceAcc);

    // alice has cash and other assets
    tester.symmetricManagerAdjustment(aliceAcc, bobAcc, cash, 0, 1000e18);
    vm.expectRevert(IBaseManager.BM_InvalidForceWithdrawAccountState.selector);
    tester.forceWithdrawAccount(aliceAcc);
  }

  // alice open 10 long call, 10 short put
  function _openDefaultPositions() internal returns (uint callSubId, uint putSubId) {
    vm.prank(bob);
    subAccounts.approve(alice, bobAcc);

    callSubId = 100;
    putSubId = 200;

    ISubAccounts.AssetTransfer[] memory transfers = new ISubAccounts.AssetTransfer[](2);

    transfers[0] = ISubAccounts.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAsset(option),
      subId: callSubId,
      amount: 10e18,
      assetData: ""
    });
    transfers[1] = ISubAccounts.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: IAsset(option),
      subId: putSubId,
      amount: 10e18,
      assetData: ""
    });

    vm.prank(alice);
    subAccounts.submitTransfers(transfers, "");
  }
}
