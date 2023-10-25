// SPDX-License-Identifier: UNLICENSED
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

    vm.startPrank(bob);
    auction.bid(aliceAcc, newAcc, 1e18, 0, 0);

    uint usdcBefore = usdc.balanceOf(bob);
    cash.withdraw(bobAcc, 100e6, bob);
    uint usdcAfter = usdc.balanceOf(bob);
    assertEq(usdcAfter, usdcBefore + 100e6);
  }

  /// high netSettledCash
  function testExchangeRateIsStableWithLargeNetSettledCash() public {
    srm.setBorrowingEnabled(true);
    srm.setBaseAssetMarginFactor(markets["weth"].id, 1e18);

    _setSpotPrice("weth", 4000e18, 1e18);
    _depositBase("weth", alice, aliceAcc, 1000e18);

    vm.startPrank(alice);
    cash.withdraw(aliceAcc, usdc.balanceOf(address(cash)), alice);

    console2.log(cash.getCurrentInterestRate());
    console2.log(cash.getCashToStableExchangeRate());
  }

  function _tradeCall(uint strike) public {
    uint96 callId = getSubId(expiry, strike, true);
    _submitTrade(aliceAcc, option, callId, 1e18, bobAcc, cash, 0, 0);
  }
}
