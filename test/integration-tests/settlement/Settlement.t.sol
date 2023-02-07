// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../shared/IntegrationTestBase.sol";
import "src/interfaces/IManager.sol";
import "src/libraries/OptionEncoding.sol";

/**
 * @dev testing settlement logic
 */
contract INTEGRATION_Settlement is IntegrationTestBase {
  address alice = address(0xaa);
  uint aliceAcc;

  address bob = address(0xbb);
  uint bobAcc;

  // value used for test
  uint constant initCash = 5000e18;
  int constant amountOfContracts = 10e18;
  uint constant strike = 2000e18;

  uint96 callId;
  uint96 putId;

  // expiry = 7 days
  uint expiry;

  function setUp() public {
    _setupIntegrationTestComplete();

    aliceAcc = accounts.createAccount(alice, pcrm);
    bobAcc = accounts.createAccount(bob, pcrm);

    // allow this contract to submit trades
    vm.prank(alice);
    accounts.setApprovalForAll(address(this), true);
    vm.prank(bob);
    accounts.setApprovalForAll(address(this), true);

    // init setup for both accounts
    _depositCash(alice, aliceAcc, initCash);
    _depositCash(bob, bobAcc, initCash);

    expiry = block.timestamp + 7 days;

    callId = OptionEncoding.toSubId(expiry, strike, true);
    putId = OptionEncoding.toSubId(expiry, strike, false);
  }

  // only settle alice's account at expiry
  function testSettleShortCallImbalance() public {
    _tradeCall();

    // stimulate expiry price
    vm.warp(expiry);
    _setSpotPriceAndSubmitForExpiry(2500e18, expiry);

    int aliceCashBefore = getCashBalance(aliceAcc);
    uint oiBefore = option.openInterest(callId);

    pcrm.settleAccount(aliceAcc);
    int aliceCashAfter = getCashBalance(aliceAcc);
    uint oiAfter = option.openInterest(callId);

    // payout is 500 USDC per contract
    int expectedPayout = 500 * amountOfContracts;

    assertEq(aliceCashAfter, aliceCashBefore - expectedPayout);

    // we have net burn
    assertEq(cash.netSettledCash(), -expectedPayout);
    _assertCashSolvent();

    // total positive is the same, no change of OI
    assertEq(oiAfter, oiBefore);
  }

  // only settle bob's account after expiry
  function testSettleLongCallImbalance() public {
    _tradeCall();

    // stimulate expiry price
    vm.warp(expiry);
    _setSpotPriceAndSubmitForExpiry(2500e18, expiry);

    int bobCashBefore = getCashBalance(bobAcc);

    pcrm.settleAccount(bobAcc);
    int bobCashAfter = getCashBalance(bobAcc);
    uint oiAfter = option.openInterest(callId);

    // payout is 500 USDC per contract
    int expectedPayout = 500 * amountOfContracts;

    assertEq(bobCashAfter, bobCashBefore + expectedPayout);

    // we have net print to bob's account
    assertEq(cash.netSettledCash(), expectedPayout);
    _assertCashSolvent();

    assertEq(oiAfter, 0);
  }

  // only settle alice's account at expiry
  function testSettleShortPutImbalance() public {
    _tradePut();

    // stimulate expiry price
    vm.warp(expiry);
    _setSpotPriceAndSubmitForExpiry(1500e18, expiry);

    int aliceCashBefore = getCashBalance(aliceAcc);

    pcrm.settleAccount(aliceAcc);
    int aliceCashAfter = getCashBalance(aliceAcc);

    // payout is 500 USDC per contract
    int expectedPayout = 500 * amountOfContracts;

    assertEq(aliceCashAfter, aliceCashBefore - expectedPayout);

    // we have net burn
    assertEq(cash.netSettledCash(), -expectedPayout);

    _assertCashSolvent();
  }

  // only settle bob's account at expiry
  function testSettleLongPutImbalance() public {
    _tradePut();

    // stimulate expiry price
    vm.warp(expiry);
    _setSpotPriceAndSubmitForExpiry(1500e18, expiry);

    int bobCashBefore = getCashBalance(bobAcc);

    pcrm.settleAccount(bobAcc);
    int bobCashAfter = getCashBalance(bobAcc);
    uint oiAfter = option.openInterest(putId);

    // payout is 500 USDC per contract
    int expectedPayout = 500 * amountOfContracts;

    assertEq(bobCashAfter, bobCashBefore + expectedPayout);

    // we have net print to Bob
    assertEq(cash.netSettledCash(), expectedPayout);

    _assertCashSolvent();

    assertEq(oiAfter, 0);
  }

  ///@dev alice go short, bob go long
  function _tradeCall() public {
    int premium = 500e18;
    // alice send call to bob, bob send premium to alice
    _submitTrade(aliceAcc, option, callId, amountOfContracts, bobAcc, cash, 0, premium);
  }

  function _tradePut() public {
    int premium = 500e18;
    // alice send put to bob, bob send premium to alice
    _submitTrade(aliceAcc, option, putId, amountOfContracts, bobAcc, cash, 0, premium);
  }
}
