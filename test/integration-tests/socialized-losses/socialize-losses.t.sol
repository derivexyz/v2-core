// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../shared/IntegrationTestBase.sol";
import "src/interfaces/IManager.sol";
import "src/libraries/OptionEncoding.sol";

/**
 * @dev insolvent auction leads to socialize losses
 */
contract INTEGRATION_SocializeLosses is IntegrationTestBase {
  address charlie = address(0xcc);

  // value used for test
  uint aliceCollat = 4000e18;
  uint initSMFund = 1000e18;

  int constant amountOfContracts = 10e18;
  uint constant strike = 2000e18;

  uint96 callId;

  // expiry = 7 days
  uint expiry;

  function setUp() public {
    _setupIntegrationTestComplete();

    // init setup for both accounts
    _depositCash(alice, aliceAcc, aliceCollat);
    _depositCash(bob, bobAcc, DEFAULT_DEPOSIT);

    expiry = block.timestamp + 7 days;
    callId = OptionEncoding.toSubId(expiry, strike, true);

    // alice will be slightly above init margin ($50)
    _openPosition();

    // charlie deposits into security module
    _depositSecurityModule(charlie, initSMFund);
  }

  // whole flow from being insolvent => no enough fund in sm => socialized losses
  function testSocializeLosses() public {
    // price went up 200%, now alice is mega insolvent
    _setSpotPriceE18(ETH_PRICE * 2);

    int initMargin = getAccInitMargin(aliceAcc);
    assertEq(initMargin / 1e18, -28617); // -23K underwater

    // start auction on alice's account
    auction.startAuction(aliceAcc);

    vm.warp(block.timestamp + _getDefaultAuctionParam().lengthOfAuction + 1);
    auction.convertToInsolventAuction(aliceAcc);

    // increase step size several times
    for (uint i = 0; i < 30; i++) {
      vm.warp(block.timestamp + _getDefaultAuctionParam().secBetweenSteps + 1);
      auction.incrementInsolventAuction(aliceAcc);
    }

    uint supplyBefore = cash.totalSupply();

    int bidPrice = auction.getCurrentBidPrice(aliceAcc);
    assertEq(bidPrice / 1e18, -4292); // bidding now will require security module to pay out $3573

    // bid from bob
    vm.prank(bob);
    auction.bid(aliceAcc, bobAcc, 1e18);

    uint supplyAfter = cash.totalSupply();

    // now all positions are closed
    assertEq(option.openInterest(callId), 0);
    assertEq(getCashBalance(aliceAcc), 0);

    // withdraw fee enabled
    assertEq(cash.temporaryWithdrawFeeEnabled(), true);

    // we printed "insolvent amount - sm fund" USD in cash
    assertEq(supplyAfter - supplyBefore, uint(-bidPrice) - initSMFund);

    uint socializedExchangeRate = cash.getCashToStableExchangeRate();
    assertLt(socializedExchangeRate, 1e18); // < 1, around 0.79

    uint usdcBefore = usdc.balanceOf(bob);
    int cashBefore = getCashBalance(bobAcc);

    // to withdraw 1000 USDC, now you burn way more cash
    _withdrawCash(bob, bobAcc, 1000e18);

    uint usdcAfter = usdc.balanceOf(bob);
    int cashAfter = getCashBalance(bobAcc);

    // successfully withdraw 1000 USDC
    assertEq((usdcAfter - usdcBefore), 1000e6);
    assertEq((cashBefore - cashAfter), int(1000e18 * 1e18 / socializedExchangeRate));
    // assertEq((cashBefore - cashAfter), 1257_300000001245745883); // 1257 cash burned
  }

  ///@dev alice go short, bob go long
  function _openPosition() public {
    int premium = 300e18 * 10; // 10 calls
    // alice send call to bob, bob send premium to alice
    _submitTrade(aliceAcc, option, callId, amountOfContracts, bobAcc, cash, 0, premium);
  }
}
