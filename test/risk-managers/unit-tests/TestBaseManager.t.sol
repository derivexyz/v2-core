// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "openzeppelin/token/ERC20/IERC20.sol";
import "lyra-utils/encoding/OptionEncoding.sol";

import {IManager} from "src/interfaces/IManager.sol";
import {ICashAsset} from "src/interfaces/ICashAsset.sol";
import {IOption} from "src/interfaces/IOption.sol";

import "src/SubAccounts.sol";
import "src/risk-managers/PortfolioViewer.sol";

import "src/feeds/AllowList.sol";

import {MockAsset} from "../../shared/mocks/MockAsset.sol";
import "../../shared/mocks/MockERC20.sol";
import "../../shared/mocks/MockFeeds.sol";
import "../../shared/mocks/MockOption.sol";
import "../../auction/mocks/MockCashAsset.sol";
import "../../shared/mocks/MockPerp.sol";
import "../mocks/BaseManagerTester.sol";
import "../mocks/MockDutchAuction.sol";

contract UNIT_TestBaseManager is Test {
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

  MockDutchAuction mockAuction;
  PortfolioViewer viewer;

  function setUp() public {
    subAccounts = new SubAccounts("Lyra Accounts", "LyraAccount");

    feed = new MockFeeds();
    usdc = new MockERC20("USDC", "USDC");
    option = new MockOption(subAccounts);
    perp = new MockPerp(subAccounts);
    cash = new MockCash(usdc, subAccounts);
    mockAuction = new MockDutchAuction();

    viewer = new PortfolioViewer(subAccounts, cash);

    tester =
      new BaseManagerTester(subAccounts, feed, feed, feed, cash, option, perp, IDutchAuction(mockAuction), viewer);

    // viewer.setStandardManager(IStandardManager(tester));

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

  function testSetSettlementBuffer() public {
    tester.setSettlementBuffer(10 minutes);
    assertEq(tester.optionSettlementBuffer(), 10 minutes);
  }

  function testCannotSetInvalidSettlementBuffer() public {
    vm.expectRevert(IBaseManager.BM_InvalidSettlementBuffer.selector);
    tester.setSettlementBuffer(3 days);
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

  function testSettingOIFeeTooHigh() public {
    viewer.setOIFeeRateBPS(address(option), 0.2e18);
    vm.expectRevert(IPortfolioViewer.BM_OIFeeRateTooHigh.selector);
    viewer.setOIFeeRateBPS(address(option), 0.2e18 + 1);

    tester.setMinOIFee(100e18);
    vm.expectRevert(IBaseManager.BM_MinOIFeeTooHigh.selector);
    tester.setMinOIFee(100e18 + 1);
  }

  /* ------------------------- *
   *    Test OI fee getters    *
   * ------------------------- **/

  function testOptionFeeIfOIIncrease() public {
    viewer.setOIFeeRateBPS(address(option), 0.001e18);
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
    viewer.setOIFeeRateBPS(address(option), 0.001e18);
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
    viewer.setOIFeeRateBPS(address(perp), 0.001e18);

    feed.setSpot(5000e18, 1e18);
    perp.setMockPerpPrice(5000e18, 1e18);

    uint tradeId = 5;

    // OI increase
    perp.setMockedOISnapshotBeforeTrade(0, tradeId, 0);
    perp.setMockedOI(0, 100e18);

    // fee = 1 * 0.1% * 5000;
    assertEq(tester.getPerpOIFee(perp, 1e18, tradeId), 5e18);
  }

  function testNoPerpFeeIfOIDecrease() public {
    viewer.setOIFeeRateBPS(address(option), 0.001e18);
    feed.setSpot(6000e18, 1e18);
    uint tradeId = 5;

    // OI increase
    perp.setMockedOISnapshotBeforeTrade(0, tradeId, 100e18);
    perp.setMockedOI(0, 0);

    assertEq(tester.getPerpOIFee(perp, 1e18, tradeId), 0);
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
    tester.executeBid(aliceAcc, bobAcc, 0.5e18, 0, 0);
  }

  function testCannotExecuteInvalidBid() external {
    vm.startPrank(address(mockAuction));
    vm.expectRevert(IBaseManager.BM_InvalidBidPortion.selector);
    tester.executeBid(aliceAcc, bobAcc, 1.2e18, 0, 0);
    vm.stopPrank();
  }

  function testCannotExecuteBidIfLiquidatorHoldsNonCash() external {
    vm.startPrank(address(mockAuction));

    tester.symmetricManagerAdjustment(aliceAcc, bobAcc, mockAsset, 0, 1e18);
    vm.expectRevert(IBaseManager.BM_LiquidatorCanOnlyHaveCash.selector);
    tester.executeBid(aliceAcc, bobAcc, 0.5e18, 0, 0);

    vm.stopPrank();
  }

  function testCannotExecuteBidIfHoldTooManyAssets() external {
    vm.startPrank(address(mockAuction));

    // balance[0] is cash
    tester.symmetricManagerAdjustment(aliceAcc, bobAcc, cash, 0, 1e18);
    // balance[1] is not cash
    tester.symmetricManagerAdjustment(aliceAcc, bobAcc, mockAsset, 0, 1e18);
    vm.expectRevert(IBaseManager.BM_LiquidatorCanOnlyHaveCash.selector);
    tester.executeBid(aliceAcc, bobAcc, 0.5e18, 0, 0);

    vm.stopPrank();
  }

  function testExecuteBidFromBidderWithNoCash() external {
    // under some edge cases, people should be able to just "receive" the portfolio without paying anything
    // for example at the end of insolvent auction, anyone can use a empty account to receive the portfolio + initial margin

    // alice' portfolio
    mockAsset.deposit(aliceAcc, 0, 1e18);
    mockAsset.deposit(aliceAcc, 1, 1e18);

    vm.startPrank(address(mockAuction));
    tester.executeBid(aliceAcc, bobAcc, 1e18, 0, 0);

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

    vm.startPrank(address(mockAuction));

    // liquidate 80%
    tester.executeBid(aliceAcc, bobAcc, 0.8e18, bid, 0);

    assertEq(subAccounts.getBalance(aliceAcc, mockAsset, 0), 40e18);
    assertEq(subAccounts.getBalance(aliceAcc, cash, 0), int(bid));

    assertEq(subAccounts.getBalance(bobAcc, mockAsset, 0), 160e18);
    assertEq(subAccounts.getBalance(bobAcc, cash, 0), 70e18); // cas

    vm.stopPrank();
  }

  function testExecuteBidWithReservedCash() external {
    // alice' portfolio: 300 cash, 200 other asset
    cash.deposit(aliceAcc, 0, 300e18);
    mockAsset.deposit(aliceAcc, 0, 200e18);

    // bob's portfolio 100 cash
    cash.deposit(bobAcc, 0, 100e18);
    uint bid = 30e18;

    // bob pays 30 to get 20% of (300 - 20 (reserved)) cash and 20% of 200 other asset

    vm.startPrank(address(mockAuction));

    // liquidate 80%, but reserve 20 cash
    tester.executeBid(aliceAcc, bobAcc, 0.2e18, bid, 20e18);

    assertEq(subAccounts.getBalance(aliceAcc, mockAsset, 0), 160e18, "alice asset");
    // alice should have: (300 - 20) * 0.8 + bid + reserved
    assertEq(subAccounts.getBalance(aliceAcc, cash, 0), int(bid + 224e18 + 20e18), "alice cash");

    assertEq(subAccounts.getBalance(bobAcc, mockAsset, 0), 40e18, "bob asset");
    assertEq(subAccounts.getBalance(bobAcc, cash, 0), 70e18 + 56e18, "bob cash");

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

    vm.startPrank(address(mockAuction));
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

    // assertEq(address(tester.allowList()), address(allowlist));
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

  function testMergeAccounts() public {
    int amount = 10e18;

    // setup some portfolio:
    // alice: 10 cash, 10 mockAsset1, -10 mockAsset2
    // bob: -10 cash, 10 mockAsset1, 10 mockAsset2

    mockAsset.deposit(aliceAcc, 1, uint(amount));
    mockAsset.deposit(bobAcc, 1, uint(amount));
    tester.symmetricManagerAdjustment(aliceAcc, bobAcc, mockAsset, 2, amount);
    tester.symmetricManagerAdjustment(bobAcc, aliceAcc, cash, 0, amount);

    uint[] memory toMerge = new uint[](1);
    toMerge[0] = bobAcc;

    // cannot initiate from non-owner
    vm.expectRevert(IBaseManager.BM_OnlySubAccountOwner.selector);
    tester.mergeAccounts(aliceAcc, toMerge);

    // cannot merge bob's account!
    vm.prank(alice);
    vm.expectRevert(IBaseManager.BM_MergeOwnerMismatch.selector);
    tester.mergeAccounts(aliceAcc, toMerge);

    // So then transfer alice's account to bob
    vm.prank(alice);
    subAccounts.transferFrom(alice, bob, aliceAcc);

    // and now they can merge!
    vm.prank(bob);
    tester.mergeAccounts(aliceAcc, toMerge);

    // perps cancel out, leaving bob with double the cash!
    ISubAccounts.AssetBalance[] memory result = subAccounts.getAccountBalances(aliceAcc);

    // alice only has 1 asset left
    assertEq(result.length, 1);
    assertEq(address(result[0].asset), address(mockAsset));
    assertEq(result[0].subId, 1);
    assertEq(result[0].balance, 2 * amount);
  }

  //////////////////////////
  //   Force Withdrawal   //
  //////////////////////////

  function testCantForceWithdrawWithNoAllowlist() public {
    vm.expectRevert(IBaseManager.BM_OnlyBlockedAccounts.selector);
    tester.forceLiquidateAccount(aliceAcc, 0);
  }

  function testCantForceLiquidateOnlyCashAccount() public {
    tester.setAllowList(feed);

    ISubAccounts.AssetBalance[] memory balances = new ISubAccounts.AssetBalance[](1);
    balances[0] = ISubAccounts.AssetBalance({asset: IAsset(cash), subId: 0, balance: 100e18});

    tester.setBalances(aliceAcc, balances);

    vm.expectRevert(IBaseManager.BM_InvalidForceLiquidateAccountState.selector);
    tester.forceLiquidateAccount(aliceAcc, 0);
  }

  function testCanForceLiquidateAccountSuccessfully() public {
    tester.setAllowList(feed);

    ISubAccounts.AssetBalance[] memory balances = new ISubAccounts.AssetBalance[](2);
    balances[0] = ISubAccounts.AssetBalance({asset: IAsset(cash), subId: 0, balance: 100e18});
    balances[1] = ISubAccounts.AssetBalance({asset: IAsset(mockAsset), subId: 0, balance: 10e18});

    tester.setBalances(aliceAcc, balances);

    tester.forceLiquidateAccount(aliceAcc, 0);
  }

  ///////////////////////////
  //   Undo Asset Deltas   //
  ///////////////////////////

  function testUndoAssetDeltasToZero() public {
    ISubAccounts.AssetBalance[] memory balances = new ISubAccounts.AssetBalance[](2);
    balances[0] = ISubAccounts.AssetBalance({asset: IAsset(cash), subId: 0, balance: 100e18});
    balances[1] = ISubAccounts.AssetBalance({asset: IAsset(mockAsset), subId: 0, balance: 10e18});

    tester.setBalances(aliceAcc, balances);

    ISubAccounts.AssetDelta[] memory deltas = new ISubAccounts.AssetDelta[](2);
    deltas[0] = ISubAccounts.AssetDelta({asset: IAsset(cash), subId: 0, delta: 100e18});
    deltas[1] = ISubAccounts.AssetDelta({asset: IAsset(mockAsset), subId: 0, delta: 10e18});
    ISubAccounts.AssetBalance[] memory res = viewer.undoAssetDeltas(aliceAcc, deltas);
    assertEq(res.length, 0);
  }

  function testUndoAssetDeltasEmptyCurrentAccount() public {
    ISubAccounts.AssetBalance[] memory balances = new ISubAccounts.AssetBalance[](0);
    tester.setBalances(aliceAcc, balances);

    ISubAccounts.AssetDelta[] memory deltas = new ISubAccounts.AssetDelta[](2);
    deltas[0] = ISubAccounts.AssetDelta({asset: IAsset(cash), subId: 0, delta: -100e18});
    // 0 delta is ignored
    deltas[1] = ISubAccounts.AssetDelta({asset: IAsset(mockAsset), subId: 0, delta: 0});
    ISubAccounts.AssetBalance[] memory res = viewer.undoAssetDeltas(aliceAcc, deltas);
    assertEq(res.length, 1);
    assertEq(res[0].balance, 100e18);
  }

  function testUndoAssetDeltasZeroDelta() public {
    ISubAccounts.AssetBalance[] memory balances = new ISubAccounts.AssetBalance[](1);
    balances[0] = ISubAccounts.AssetBalance({asset: IAsset(cash), subId: 0, balance: 100e18});
    tester.setBalances(aliceAcc, balances);

    ISubAccounts.AssetDelta[] memory deltas = new ISubAccounts.AssetDelta[](1);
    deltas[0] = ISubAccounts.AssetDelta({asset: IAsset(cash), subId: 0, delta: 0});

    ISubAccounts.AssetBalance[] memory res = viewer.undoAssetDeltas(aliceAcc, deltas);
    assertEq(res.length, 1);
    assertEq(res[0].balance, 100e18);
  }

  /////////////////
  //   Helpers   //
  /////////////////

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
