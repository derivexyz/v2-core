// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "openzeppelin/token/ERC20/IERC20.sol";

import "src/interfaces/IManager.sol";
import "src/interfaces/ICashAsset.sol";
import "src/interfaces/IOption.sol";
import "src/interfaces/IChainlinkSpotFeed.sol";
import "src/interfaces/AccountStructs.sol";

import "src/Accounts.sol";
import "src/risk-managers/BaseManager.sol";

import "../../shared/mocks/MockAsset.sol";
import "../../shared/mocks/MockERC20.sol";
import "../../shared/mocks/MockFeed.sol";
import "../../shared/mocks/MockOption.sol";
import "../../auction/mocks/MockCashAsset.sol";

contract BaseManagerTester is BaseManager {
  constructor(
    IAccounts accounts_,
    IFutureFeed futureFeed_,
    ISettlementFeed settlementFeed_,
    ICashAsset cash_,
    IOption option_
  ) BaseManager(accounts_, futureFeed_, settlementFeed_, cash_, option_) {}

  function symmetricManagerAdjustment(uint from, uint to, IAsset asset, uint96 subId, int amount) external {
    _symmetricManagerAdjustment(from, to, asset, subId, amount);
  }

  function chargeOIFee(uint accountId, uint feeRecipientAcc, uint tradeId, AssetDelta[] calldata assetDeltas) external {
    _chargeOIFee(accountId, feeRecipientAcc, tradeId, assetDeltas);
  }

  function addOption(Portfolio memory portfolio, AccountStructs.AssetBalance memory asset)
    external
    pure
    returns (Portfolio memory updatedPortfolio)
  {
    _addOption(portfolio, asset);
    return portfolio;
  }

  function handleAdjustment(
    uint, /*accountId*/
    uint, /*tradeId*/
    address,
    AssetDelta[] calldata, /*assetDeltas*/
    bytes memory
  ) public {}

  function handleManagerChange(uint, IManager) external {}
}

contract UNIT_TestAbstractBaseManager is AccountStructs, Test {
  Accounts accounts;
  BaseManagerTester tester;

  MockAsset mockAsset;
  MockFeed feed;
  MockERC20 usdc;
  MockOption option;
  MockCash cash;

  address alice = address(0xaa);
  address bob = address(0xb0ba);

  uint aliceAcc;
  uint bobAcc;
  uint feeRecipientAcc;

  function setUp() public {
    accounts = new Accounts("Lyra Accounts", "LyraAccount");

    feed = new MockFeed();
    usdc = new MockERC20("USDC", "USDC");
    option = new MockOption(accounts);
    cash = new MockCash(usdc, accounts);

    tester = new BaseManagerTester(accounts, feed, feed, cash, option);

    mockAsset = new MockAsset(IERC20(address(0)), accounts, true);

    aliceAcc = accounts.createAccount(alice, IManager(address(tester)));

    bobAcc = accounts.createAccount(bob, IManager(address(tester)));

    feeRecipientAcc = accounts.createAccount(address(this), IManager(address(tester)));
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

  function testBlockTradeIfMultipleExpiries() public {
    // initial portfolio
    IBaseManager.Strike[] memory strikes = new IBaseManager.Strike[](1);
    strikes[0] = IBaseManager.Strike({strike: 1000e18, calls: 1e18, puts: 0, forwards: 0});
    IBaseManager.Portfolio memory portfolio =
      IBaseManager.Portfolio({cash: 0, expiry: 1 days, numStrikesHeld: 1, strikes: strikes});

    // construct asset
    AccountStructs.AssetBalance memory assetBalance = AccountStructs.AssetBalance({
      asset: IAsset(address(option)),
      subId: OptionEncoding.toSubId(block.timestamp + 1.2 days, 1000e18, true),
      balance: 10e18
    });

    vm.expectRevert(BaseManager.BM_OnlySingleExpiryPerAccount.selector);
    tester.addOption(portfolio, assetBalance);
  }

  function testAddOption() public {
    // initial portfolio
    uint expiry = block.timestamp + 1 days;
    IBaseManager.Strike[] memory strikes = new IBaseManager.Strike[](5);
    strikes[0] = IBaseManager.Strike({strike: 1000e18, calls: -5e18, puts: 0, forwards: 0});
    strikes[1] = IBaseManager.Strike({strike: 2000e18, calls: -1e18, puts: 0, forwards: 0});
    strikes[2] = IBaseManager.Strike({strike: 3000e18, calls: 10e18, puts: 5e18, forwards: 0});
    BaseManager.Portfolio memory portfolio =
      IBaseManager.Portfolio({cash: 0, expiry: expiry, numStrikesHeld: 3, strikes: strikes});

    // add call to existing strike
    AccountStructs.AssetBalance memory assetBalance = AccountStructs.AssetBalance({
      asset: IAsset(address(option)),
      subId: OptionEncoding.toSubId(expiry, 1000e18, true),
      balance: 10e18
    });
    IBaseManager.Portfolio memory updatedPortfolio = tester.addOption(portfolio, assetBalance);
    assertEq(updatedPortfolio.strikes[0].calls, 5e18);

    // add put to existing strike
    assetBalance = AccountStructs.AssetBalance({
      asset: IAsset(address(option)),
      subId: OptionEncoding.toSubId(expiry, 2000e18, false),
      balance: -100e18
    });
    updatedPortfolio = tester.addOption(portfolio, assetBalance);
    assertEq(updatedPortfolio.strikes[1].puts, -100e18);

    // add put to new strike
    assetBalance = AccountStructs.AssetBalance({
      asset: IAsset(address(option)),
      subId: OptionEncoding.toSubId(expiry, 20000e18, false),
      balance: 1e18
    });
    updatedPortfolio = tester.addOption(portfolio, assetBalance);
    assertEq(updatedPortfolio.strikes[3].puts, 1e18);
    assertEq(updatedPortfolio.numStrikesHeld, 4);
  }

  /* ----------------- *
   *    Test OI fee    *
   * ---------------- **/

  function testChargeFeeOn1SubIdIfOIIncreased() public {
    uint spot = 2000e18;
    feed.setSpot(spot);

    uint96 subId = 1;
    uint tradeId = 5;
    int amount = 1e18;

    // OI increase
    option.setMockedOISnapshotBeforeTrade(subId, tradeId, 0);
    option.setMockedOI(subId, 100e18);

    AssetDelta[] memory assetDeltas = new AssetDelta[](1);
    assetDeltas[0] = AssetDelta(option, subId, amount);

    int cashBefore = accounts.getBalance(feeRecipientAcc, cash, 0);
    tester.chargeOIFee(aliceAcc, feeRecipientAcc, tradeId, assetDeltas);

    int fee = accounts.getBalance(feeRecipientAcc, cash, 0) - cashBefore;
    // fee = 1 * 0.1% * 2000;
    assertEq(fee, 2e18);
  }

  function testShouldNotChargeFeeIfOIDecrease() public {
    uint spot = 2000e18;
    feed.setSpot(spot);

    uint96 subId = 1;
    uint tradeId = 5;
    int amount = 1e18;

    // OI decrease
    option.setMockedOISnapshotBeforeTrade(subId, tradeId, 100e18);
    option.setMockedOI(subId, 0);

    AssetDelta[] memory assetDeltas = new AssetDelta[](1);
    assetDeltas[0] = AssetDelta(option, subId, amount);

    int cashBefore = accounts.getBalance(feeRecipientAcc, cash, 0);
    tester.chargeOIFee(aliceAcc, feeRecipientAcc, tradeId, assetDeltas);

    // no fee: balance stays the same
    assertEq(accounts.getBalance(feeRecipientAcc, cash, 0), cashBefore);
  }

  function testShouldNotChargeFeeOnOtherAssetsThenCash() public {
    int amount = -2000e18;

    AssetDelta[] memory assetDeltas = new AssetDelta[](1);
    assetDeltas[0] = AssetDelta(cash, 0, amount);

    int cashBefore = accounts.getBalance(feeRecipientAcc, cash, 0);
    tester.chargeOIFee(aliceAcc, feeRecipientAcc, 0, assetDeltas);

    // no fee: balance stays the same
    assertEq(accounts.getBalance(feeRecipientAcc, cash, 0), cashBefore);
  }

  function testOnlyChargeFeeOnSubIDWIthOIIncreased() public {
    uint spot = 2000e18;
    feed.setSpot(spot);

    (uint96 subId1, uint96 subId2, uint96 subId3) = (1, 2, 3);
    uint tradeId = 5;
    int amount = 10e18;

    // subId2 and subId2 OI increase
    option.setMockedOI(subId2, 100e18);
    option.setMockedOI(subId3, 100e18);

    AssetDelta[] memory assetDeltas = new AssetDelta[](3);
    assetDeltas[0] = AssetDelta(option, subId1, amount);
    assetDeltas[1] = AssetDelta(option, subId2, -amount);
    assetDeltas[2] = AssetDelta(option, subId3, amount);

    int cashBefore = accounts.getBalance(feeRecipientAcc, cash, 0);
    tester.chargeOIFee(aliceAcc, feeRecipientAcc, tradeId, assetDeltas);

    // no fee: balance stays the same
    int fee = accounts.getBalance(feeRecipientAcc, cash, 0) - cashBefore;
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

    tester.settleAccount(aliceAcc);

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

    tester.settleAccount(aliceAcc);

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

    tester.settleAccount(aliceAcc);

    assertEq(accounts.getBalance(aliceAcc, option, callId), callBalanceBefore);
    assertEq(accounts.getBalance(aliceAcc, option, putId), putBalanceBefore);
    // cash increase
    assertEq(accounts.getBalance(aliceAcc, cash, 0), 0);
  }

  function testSettlementBatch() external {
    (uint callId, uint putId) = _openDefaultPositions();

    // mock settlement value
    option.setMockedSubIdSettled(callId, true);
    option.setMockedSubIdSettled(putId, true);
    option.setMockedTotalSettlementValue(callId, -500e18);
    option.setMockedTotalSettlementValue(putId, 1000e18);

    uint[] memory accountsToSettle = new uint[](2);
    accountsToSettle[0] = aliceAcc;
    accountsToSettle[1] = bobAcc;
    tester.batchSettleAccounts(accountsToSettle);

    assertEq(accounts.getBalance(aliceAcc, option, callId), 0);
    assertEq(accounts.getBalance(aliceAcc, option, putId), 0);

    assertEq(accounts.getBalance(bobAcc, option, callId), 0);
    assertEq(accounts.getBalance(bobAcc, option, putId), 0);

    // cash increase for both. (because the payout is mocked to be the same)
    assertEq(accounts.getBalance(aliceAcc, cash, 0), 500e18);
    assertEq(accounts.getBalance(bobAcc, cash, 0), 500e18);
  }

  // alice open 10 long call, 10 short put
  function _openDefaultPositions() internal returns (uint callSubId, uint putSubId) {
    vm.prank(bob);
    accounts.approve(alice, bobAcc);

    callSubId = 100;
    putSubId = 200;

    AccountStructs.AssetTransfer[] memory transfers = new AccountStructs.AssetTransfer[](2);

    transfers[0] = AccountStructs.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAsset(option),
      subId: callSubId,
      amount: 10e18,
      assetData: ""
    });
    transfers[1] = AccountStructs.AssetTransfer({
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
