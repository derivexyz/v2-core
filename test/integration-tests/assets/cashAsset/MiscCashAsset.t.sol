// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "forge-std/console2.sol";

import "../../shared/IntegrationTestBase.t.sol";

contract INTEGRATION_CashAssetMisc is IntegrationTestBase {
  using DecimalMath for uint;

  uint64 expiry;
  IOptionAsset option;

  function setUp() public {
    _setupIntegrationTestComplete();

    option = markets["weth"].option;

    // Alice and Bob deposit cash into the system
    _depositCash(address(alice), aliceAcc, 2000e18);
    _depositCash(address(bob), bobAcc, 2000e18);

    expiry = uint64(block.timestamp + 1 weeks);
    // set forward price for expiry
    _setForwardPrice("weth", expiry, 2000e18, 1e18);
    _setDefaultSVIForExpiry("weth", expiry);

    //    auction.setWithdrawBlockThreshold(-100e18);
  }

  /// Withdraw lock

  function testBigInsolventAuctionLockWithdraw() public {
    auction.setSMAccount(smAcc);

    // trade 2000 call
    _tradeCall(2000e18);

    _setSpotPrice("weth", 4000e18, 1e18);
    _setForwardPrice("weth", expiry, 4000e18, 1e18);

    // alice is ultra insolvent
    auction.startAuction(aliceAcc, 1);

    // bob cannot withdraw cash
    vm.prank(bob);
    vm.expectRevert(ICashAsset.CA_WithdrawBlockedByOngoingAuction.selector);
    cash.withdraw(bobAcc, 100e6, bob);
  }

  function testCanRecoverFromLock() public {
    // trade 2000 call
    _tradeCall(2000e18);

    _setSpotPrice("weth", 4000e18, 1e18);
    _setForwardPrice("weth", expiry, 4000e18, 1e18);

    // alice is ultra insolvent
    auction.startAuction(aliceAcc, 1);

    // bob can unlock by bidding the whole portfolio him self from a new acc ;)
    uint newAcc = subAccounts.createAccount(bob, srm);
    _depositCash(address(bob), newAcc, 2000e18);
  }

  /// high netSettledCash
  function testExchangeRateIsStableWithTinyNetSettledCash() public {
    srm.setBorrowingEnabled(true);
    srm.setBaseAssetMarginFactor(markets["weth"].id, 1e18, 1e18);

    _tradeCall(2000e18);

    vm.warp(expiry);
    _setSpotPrice("weth", 4000e18, 1e18);
    _setSettlementPrice("weth", expiry, 502000e18);

    srm.settleOptions(option, aliceAcc);

    assertEq(cash.netSettledCash(), -500000e18);

    // when you withdraw all cash, exchange rate is still == 1 (as totalSupply == totalBorrow)
    assertEq(cash.getCashToStableExchangeRate(), 1e18);

    // 0 interest accrued
    srm.settleInterest(aliceAcc);
    srm.settleInterest(bobAcc);

    int interest = 33_229_591160183198430000;
    // TODO: there seems to be a rounding error here
    int posInterest = 33_229_591160183198312000;

    uint snapshot = vm.snapshot();
    {
      vm.warp(block.timestamp + 10 weeks);

      // 35,000 interest...
      assertEq(cash.calculateBalanceWithInterest(aliceAcc), 2000e18 - 500_000e18 - interest);
      assertEq(cash.calculateBalanceWithInterest(bobAcc), 2_000e18 + interest);

      srm.settleOptions(option, bobAcc);
      assertEq(cash.calculateBalanceWithInterest(bobAcc), 502_000e18 + interest);
      assertEq(cash.getCashToStableExchangeRate(), 1e18);
    }

    // No difference if the option was settled or not

    vm.revertTo(snapshot);
    {
      srm.settleOptions(option, bobAcc);
      assertEq(cash.netSettledCash(), 0);

      vm.warp(block.timestamp + 10 weeks);

      assertEq(cash.calculateBalanceWithInterest(aliceAcc), -498_000e18 - interest, "a");
      // Interest is subtly different because some interest is applied to bob when the option is settled, so he has a bigger
      // portion
      assertEq(cash.calculateBalanceWithInterest(bobAcc), 502_000e18 + posInterest, "B");
      assertEq(cash.getCashToStableExchangeRate(), 1e18);
      assertEq(cash.calculateBalanceWithInterest(aliceAcc), -498_000e18 - interest, "a");
    }
  }

  /// high netSettledCash
  function testExchangeRateIsStableWithLargeNetSettledCash() public {
    srm.setBorrowingEnabled(true);
    srm.setBaseAssetMarginFactor(markets["weth"].id, 1e18, 1e18);

    _tradeCall(2000e18);

    vm.warp(expiry);
    _setSpotPrice("weth", 4000e18, 1e18);
    _setSettlementPrice("weth", expiry, 502000e18);

    srm.settleOptions(option, bobAcc);

    assertEq(cash.netSettledCash(), 500000e18);

    // when you withdraw all cash, exchange rate is still == 1 (as totalSupply == totalBorrow)
    assertEq(cash.getCashToStableExchangeRate(), 1e18);

    srm.settleInterest(aliceAcc);
    srm.settleInterest(bobAcc);

    uint snapshot = vm.snapshot();
    {
      // 0 interest accrued as the system does not know alice is insolvent yet

      vm.warp(block.timestamp + 10 weeks);

      // 35,000 interest...
      assertEq(cash.calculateBalanceWithInterest(aliceAcc), 2000e18, "a");
      assertEq(cash.calculateBalanceWithInterest(bobAcc), 502_000e18, "B");

      srm.settleOptions(option, aliceAcc);
      assertEq(cash.calculateBalanceWithInterest(bobAcc), 502_000e18, "c");
      assertEq(cash.calculateBalanceWithInterest(aliceAcc), -498_000e18, "d");
      assertEq(cash.getCashToStableExchangeRate(), 1e18);
    }

    int interest = 33_229_591160183198430000;
    // TODO: there seems to be a rounding error here
    int posInterest = 33_229_591160183198312000;

    vm.revertTo(snapshot);
    {
      // But if we settle alice at the same time, then interest begins to be charged
      srm.settleOptions(option, aliceAcc);
      assertEq(cash.netSettledCash(), 0);

      vm.warp(block.timestamp + 10 weeks);

      assertEq(cash.getCashToStableExchangeRate(), 1e18);
      // Again, subtle difference...
      assertEq(cash.calculateBalanceWithInterest(bobAcc), 502_000e18 + posInterest, "B");
      assertEq(cash.calculateBalanceWithInterest(aliceAcc), -498_000e18 - interest, "a");

      srm.settleInterest(aliceAcc);
      srm.settleInterest(bobAcc);

      assertEq(cash.calculateBalanceWithInterest(bobAcc), 502_000e18 + posInterest, "B");
      assertEq(cash.calculateBalanceWithInterest(aliceAcc), -498_000e18 - interest, "a");
      assertEq(cash.getCashToStableExchangeRate(), 1e18);
    }
  }

  /// Exchange rate when balance is 0
  function testExchangeRateIsStableWhenCashBalanceIsZero() public {
    srm.setBorrowingEnabled(true);
    srm.setBaseAssetMarginFactor(markets["weth"].id, 1e18, 1e18);

    _setSpotPrice("weth", 4000e18, 1e18);
    _depositBase("weth", alice, aliceAcc, 1000e18);

    vm.startPrank(alice);
    cash.withdraw(aliceAcc, usdc.balanceOf(address(cash)), alice);

    // when you withdraw all cash, exchange rate is still == 1 (as totalSupply == totalBorrow)
    assertEq(cash.getCashToStableExchangeRate(), 1e18);
    vm.warp(block.timestamp + 10 weeks);

    srm.settleInterest(aliceAcc);
    assertEq(cash.getCashToStableExchangeRate(), 1e18);
  }

  function _tradeCall(uint strike) public {
    uint96 callId = getSubId(expiry, strike, true);
    _submitTrade(aliceAcc, option, callId, 1e18, bobAcc, cash, 0, 0);
  }
}
