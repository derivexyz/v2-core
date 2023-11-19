// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "lyra-utils/encoding/OptionEncoding.sol";

import {IManager} from "../../../src/interfaces/IManager.sol";
import {IBaseManager} from "../../../src/interfaces/IBaseManager.sol";

import "../../../src/SubAccounts.sol";
import "../../../src/risk-managers/SRMPortfolioViewer.sol";

import {MockAsset} from "../../shared/mocks/MockAsset.sol";
import "../../shared/mocks/MockERC20.sol";
import "../../shared/mocks/MockFeeds.sol";
import "../../shared/mocks/MockOptionAsset.sol";
import "../../shared/mocks/MockCash.sol";
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
  SRMPortfolioViewer viewer;

  function setUp() public {
    subAccounts = new SubAccounts("Lyra Accounts", "LyraAccount");

    feed = new MockFeeds();
    usdc = new MockERC20("USDC", "USDC");
    option = new MockOption(subAccounts);
    perp = new MockPerp(subAccounts);
    cash = new MockCash(usdc, subAccounts);
    mockAuction = new MockDutchAuction();

    viewer = new SRMPortfolioViewer(subAccounts, cash);

    tester = new BaseManagerTester(subAccounts, feed, feed, cash, option, perp, IDutchAuction(mockAuction), viewer);

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

  function testCannotSetLiquidationToZero() public {
    vm.expectRevert(IBaseManager.BM_InvalidLiquidation.selector);
    tester.setLiquidation(IDutchAuction(address(0)));

    tester.setLiquidation(IDutchAuction(bob));
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
    vm.expectRevert(IBasePortfolioViewer.BM_OIFeeRateTooHigh.selector);
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

  function testChargeAllOIFeeCoverage() external {
    // balances
    ISubAccounts.AssetDelta[] memory assetDeltas = new ISubAccounts.AssetDelta[](0);
    vm.expectRevert(IBaseManager.BM_NotImplemented.selector);
    tester.chargeAllOIFee(address(this), 0, 0, assetDeltas);
  }

  /////////////////////////////
  // getPreviousAssetsLength //
  /////////////////////////////

  function testUndoAssetDeltasToZero() public {
    ISubAccounts.AssetBalance[] memory balances = new ISubAccounts.AssetBalance[](2);
    balances[0] = ISubAccounts.AssetBalance({asset: IAsset(cash), subId: 0, balance: 100e18});
    balances[1] = ISubAccounts.AssetBalance({asset: IAsset(mockAsset), subId: 0, balance: 10e18});

    ISubAccounts.AssetDelta[] memory deltas = new ISubAccounts.AssetDelta[](2);
    deltas[0] = ISubAccounts.AssetDelta({asset: IAsset(cash), subId: 0, delta: 100e18});
    deltas[1] = ISubAccounts.AssetDelta({asset: IAsset(mockAsset), subId: 0, delta: 10e18});

    assertEq(viewer.getPreviousAssetsLength(balances, deltas), 0);
  }

  function testUndoAssetDeltasEmptyCurrentAccount() public {
    ISubAccounts.AssetBalance[] memory balances = new ISubAccounts.AssetBalance[](0);

    ISubAccounts.AssetDelta[] memory deltas = new ISubAccounts.AssetDelta[](2);
    deltas[0] = ISubAccounts.AssetDelta({asset: IAsset(cash), subId: 0, delta: -100e18});
    // 0 delta is ignored
    deltas[1] = ISubAccounts.AssetDelta({asset: IAsset(mockAsset), subId: 0, delta: 0});

    assertEq(viewer.getPreviousAssetsLength(balances, deltas), 1);
  }

  function testUndoAssetDeltasZeroDelta() public {
    ISubAccounts.AssetBalance[] memory balances = new ISubAccounts.AssetBalance[](1);
    balances[0] = ISubAccounts.AssetBalance({asset: IAsset(cash), subId: 0, balance: 100e18});

    ISubAccounts.AssetDelta[] memory deltas = new ISubAccounts.AssetDelta[](1);
    deltas[0] = ISubAccounts.AssetDelta({asset: IAsset(cash), subId: 0, delta: 0});

    assertEq(viewer.getPreviousAssetsLength(balances, deltas), 1);
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
