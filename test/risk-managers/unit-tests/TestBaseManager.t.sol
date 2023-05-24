// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "openzeppelin/token/ERC20/IERC20.sol";
import "lyra-utils/encoding/OptionEncoding.sol";

import {IManager} from "src/interfaces/IManager.sol";
import "src/interfaces/ICashAsset.sol";
import "src/interfaces/IOption.sol";

import "src/Accounts.sol";
import "src/risk-managers/BaseManager.sol";

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
  ISettlementFeed public immutable settlementFeed;

  constructor(
    IAccounts accounts_,
    IForwardFeed forwardFeed_,
    ISettlementFeed settlementFeed_,
    ICashAsset cash_,
    IOption option_,
    IPerpAsset perp_,
    IDutchAuction auction_
  ) BaseManager(accounts_, cash_, auction_) {
    // TODO: liquidations
    option = option_;
    perp = perp_;
    forwardFeed = forwardFeed_;
    settlementFeed = settlementFeed_;
  }

  function symmetricManagerAdjustment(uint from, uint to, IAsset asset, uint96 subId, int amount) external {
    _symmetricManagerAdjustment(from, to, asset, subId, amount);
  }

  function chargeOIFee(uint accountId, uint tradeId, IAccounts.AssetDelta[] calldata assetDeltas) external {
    _chargeOIFee(option, forwardFeed, accountId, tradeId, assetDeltas);
  }

  function settleOptions(uint accountId) external {
    _settleAccountOptions(option, accountId);
  }

  function handleAdjustment(
    uint, /*accountId*/
    uint, /*tradeId*/
    address,
    IAccounts.AssetDelta[] calldata, /*assetDeltas*/
    bytes memory
  ) public {}

  function getMargin(uint, bool) external view returns (int) {}

  function getMarginAndMarkToMarket(uint accountId, bool isInitial, uint scenarioId) external view returns (int, int) {}
}

contract UNIT_TestAbstractBaseManager is Test {
  Accounts accounts;
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
    accounts = new Accounts("Lyra Accounts", "LyraAccount");

    feed = new MockFeeds();
    usdc = new MockERC20("USDC", "USDC");
    option = new MockOption(accounts);
    perp = new MockPerp(accounts);
    cash = new MockCash(usdc, accounts);

    tester = new BaseManagerTester(accounts, feed, feed, cash, option, perp, IDutchAuction(mockAuction));

    mockAsset = new MockAsset(usdc, accounts, true);

    aliceAcc = accounts.createAccount(alice, IManager(address(tester)));

    bobAcc = accounts.createAccount(bob, IManager(address(tester)));

    feeRecipientAcc = accounts.createAccount(address(this), IManager(address(tester)));

    tester.setFeeRecipient(feeRecipientAcc);

    expiry = block.timestamp + 7 days;

    usdc.mint(address(this), 2000_000e18);
    usdc.approve(address(mockAsset), 2000_000e18);
    usdc.approve(address(cash), 2000_000e18);
  }

  function testTransferWithoutMarginPositiveAmount() public {
    int amount = 5000 * 1e18;
    tester.symmetricManagerAdjustment(aliceAcc, bobAcc, mockAsset, 0, amount);

    assertEq(accounts.getBalance(aliceAcc, mockAsset, 0), -amount);
    assertEq(accounts.getBalance(bobAcc, mockAsset, 0), amount);
  }

  function testTransferWithoutMarginNegativeAmount() public {
    int amount = -5000 * 1e18;
    tester.symmetricManagerAdjustment(aliceAcc, bobAcc, mockAsset, 0, amount);

    assertEq(accounts.getBalance(aliceAcc, mockAsset, 0), -amount);
    assertEq(accounts.getBalance(bobAcc, mockAsset, 0), amount);
  }

  /* ----------------------------- *
   *    Test Option Arrangement    *
   * ---------------------------- **/

  /* ----------------- *
   *    Test OI fee    *
   * ---------------- **/

  function testChargeFeeOn1SubIdIfOIIncreased() public {
    uint spot = 2000e18;
    feed.setSpot(spot, 1e18);
    feed.setForwardPrice(expiry, spot, 1e18);

    uint96 subId = OptionEncoding.toSubId(expiry, 2500e18, true);
    uint tradeId = 5;
    int amount = 1e18;

    // OI increase
    option.setMockedOISnapshotBeforeTrade(subId, tradeId, 0);
    option.setMockedOI(subId, 100e18);

    IAccounts.AssetDelta[] memory assetDeltas = new IAccounts.AssetDelta[](1);
    assetDeltas[0] = IAccounts.AssetDelta(option, subId, amount);

    int cashBefore = accounts.getBalance(tester.feeRecipientAcc(), cash, 0);
    tester.chargeOIFee(aliceAcc, tradeId, assetDeltas);

    int fee = accounts.getBalance(tester.feeRecipientAcc(), cash, 0) - cashBefore;
    // fee = 1 * 0.1% * 2000;
    assertEq(fee, 2e18);
    assertEq(tester.feeCharged(tradeId, aliceAcc), uint(fee));
  }

  function testShouldNotChargeFeeIfOIDecrease() public {
    uint spot = 2000e18;
    feed.setSpot(spot, 1e18);
    feed.setForwardPrice(expiry, spot, 1e18);

    uint96 subId = OptionEncoding.toSubId(expiry, 2500e18, true);
    uint tradeId = 5;
    int amount = 1e18;

    // OI decrease
    option.setMockedOISnapshotBeforeTrade(subId, tradeId, 100e18);
    option.setMockedOI(subId, 0);

    IAccounts.AssetDelta[] memory assetDeltas = new IAccounts.AssetDelta[](1);
    assetDeltas[0] = IAccounts.AssetDelta(option, subId, amount);

    int cashBefore = accounts.getBalance(tester.feeRecipientAcc(), cash, 0);
    tester.chargeOIFee(aliceAcc, tradeId, assetDeltas);

    // no fee: balance stays the same
    assertEq(accounts.getBalance(tester.feeRecipientAcc(), cash, 0), cashBefore);
  }

  function testShouldNotChargeFeeOnOtherAssetsThenCash() public {
    int amount = -2000e18;

    IAccounts.AssetDelta[] memory assetDeltas = new IAccounts.AssetDelta[](1);
    assetDeltas[0] = IAccounts.AssetDelta(cash, 0, amount);

    uint tradeId = 1;

    int cashBefore = accounts.getBalance(tester.feeRecipientAcc(), cash, 0);
    tester.chargeOIFee(aliceAcc, tradeId, assetDeltas);

    // no fee: balance stays the same
    assertEq(accounts.getBalance(tester.feeRecipientAcc(), cash, 0), cashBefore);
    assertEq(tester.feeCharged(tradeId, aliceAcc), 0);
  }

  function testOnlyChargeFeeOnSubIDWIthOIIncreased() public {
    uint spot = 2000e18;
    feed.setSpot(spot, 1e18);
    feed.setForwardPrice(expiry, spot, 1e18);

    uint96 subId1 = OptionEncoding.toSubId(expiry, 2600e18, true);
    uint96 subId2 = OptionEncoding.toSubId(expiry, 2700e18, true);
    uint96 subId3 = OptionEncoding.toSubId(expiry, 2800e18, true);

    uint tradeId = 5;
    int amount = 10e18;

    // subId2 and subId2 OI increase
    option.setMockedOI(subId2, 100e18);
    option.setMockedOI(subId3, 100e18);

    IAccounts.AssetDelta[] memory assetDeltas = new IAccounts.AssetDelta[](3);
    assetDeltas[0] = IAccounts.AssetDelta(option, subId1, amount);
    assetDeltas[1] = IAccounts.AssetDelta(option, subId2, -amount);
    assetDeltas[2] = IAccounts.AssetDelta(option, subId3, amount);

    int cashBefore = accounts.getBalance(tester.feeRecipientAcc(), cash, 0);
    tester.chargeOIFee(aliceAcc, tradeId, assetDeltas);

    // no fee: balance stays the same
    int fee = accounts.getBalance(tester.feeRecipientAcc(), cash, 0) - cashBefore;
    // fee for each subId2 = 10 * 0.1% * 2000 = 20;
    // fee for each subId3 = 10 * 0.1% * 2000 = 20;
    assertEq(fee, 40e18);
  }

  function testSettlementNetPositive() external {
    (uint callId, uint putId) = _openDefaultPositions();

    // mock settlement value
    option.setMockedSubIdSettled(callId, true);
    option.setMockedSubIdSettled(putId, true);
    option.setMockedTotalSettlementValue(callId, -500e18);
    option.setMockedTotalSettlementValue(putId, 1000e18);

    tester.settleOptions(aliceAcc);

    assertEq(accounts.getBalance(aliceAcc, option, callId), 0);
    assertEq(accounts.getBalance(aliceAcc, option, putId), 0);

    // cash increase
    assertEq(accounts.getBalance(aliceAcc, cash, 0), 500e18);
  }

  function testSettlementNetNegative() external {
    (uint callId, uint putId) = _openDefaultPositions();

    // mock settlement value
    option.setMockedSubIdSettled(callId, true);
    option.setMockedSubIdSettled(putId, true);
    option.setMockedTotalSettlementValue(callId, -1500e18);
    option.setMockedTotalSettlementValue(putId, 200e18);

    tester.settleOptions(aliceAcc);

    assertEq(accounts.getBalance(aliceAcc, option, callId), 0);
    assertEq(accounts.getBalance(aliceAcc, option, putId), 0);

    // cash increase
    assertEq(accounts.getBalance(aliceAcc, cash, 0), -1300e18);
  }

  function testSettleOnUnsettledAsset() external {
    (uint callId, uint putId) = _openDefaultPositions();

    int callBalanceBefore = accounts.getBalance(aliceAcc, option, callId);
    int putBalanceBefore = accounts.getBalance(aliceAcc, option, putId);

    // mock settlement value: settled still remain false
    option.setMockedTotalSettlementValue(callId, -500e18);
    option.setMockedTotalSettlementValue(putId, 1000e18);

    tester.settleOptions(aliceAcc);

    assertEq(accounts.getBalance(aliceAcc, option, callId), callBalanceBefore);
    assertEq(accounts.getBalance(aliceAcc, option, putId), putBalanceBefore);
    // cash increase
    assertEq(accounts.getBalance(aliceAcc, cash, 0), 0);
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

    assertEq(accounts.getBalance(aliceAcc, mockAsset, 0), 0);
    assertEq(accounts.getBalance(bobAcc, mockAsset, 0), 1e18);

    assertEq(accounts.getBalance(aliceAcc, mockAsset, 1), 0);
    assertEq(accounts.getBalance(bobAcc, mockAsset, 1), 1e18);

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

    assertEq(accounts.getBalance(aliceAcc, mockAsset, 0), 40e18);
    assertEq(accounts.getBalance(aliceAcc, cash, 0), int(bid));

    assertEq(accounts.getBalance(bobAcc, mockAsset, 0), 160e18);
    assertEq(accounts.getBalance(bobAcc, cash, 0), 70e18); // cas

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

    assertEq(accounts.getBalance(aliceAcc, mockAsset, 0), int(amount));
    assertEq(accounts.getBalance(aliceAcc, cash, 0), 199e18);
  }

  // alice open 10 long call, 10 short put
  function _openDefaultPositions() internal returns (uint callSubId, uint putSubId) {
    vm.prank(bob);
    accounts.approve(alice, bobAcc);

    callSubId = 100;
    putSubId = 200;

    IAccounts.AssetTransfer[] memory transfers = new IAccounts.AssetTransfer[](2);

    transfers[0] = IAccounts.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAsset(option),
      subId: callSubId,
      amount: 10e18,
      assetData: ""
    });
    transfers[1] = IAccounts.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: IAsset(option),
      subId: putSubId,
      amount: 10e18,
      assetData: ""
    });

    vm.prank(alice);
    accounts.submitTransfers(transfers, "");
  }
}
