// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "lyra-utils/encoding/OptionEncoding.sol";

import "../shared/IntegrationTestBase.sol";
import "src/interfaces/IManager.sol";

/**
 * @dev testing settlement logic
 */
contract INTEGRATION_Settlement is IntegrationTestBase {
  using DecimalMath for uint;

  address charlie = address(0xcc);
  uint charlieAcc;

  // value used for test
  int constant amountOfContracts = 1e18;
  uint constant strike = 2000e18;

  uint96 callId;
  uint96 putId;

  // expiry = 7 days
  uint expiry;

  function setUp() public {
    _setupIntegrationTestComplete();
    charlieAcc = accounts.createAccount(charlie, pcrm);

    // allow this contract to submit trades
    vm.prank(charlie);
    accounts.setApprovalForAll(address(this), true);

    // init setup for both accounts
    _depositCash(alice, aliceAcc, DEFAULT_DEPOSIT);
    _depositCash(bob, bobAcc, DEFAULT_DEPOSIT);
    _depositCash(charlie, charlieAcc, 2e18); // initial OI Fee

    expiry = block.timestamp + 4 weeks;

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

  // Check that after all settlements printed cash is 0
  function testPrintedCashAroundSettlements() public {
    // Alice <-> Charlie trade
    _createBorrowForUser(charlie, aliceAcc, charlieAcc, 500e18);
    // Alice <-> Bob trade
    _tradeCall();

    // stimulate expiry price
    vm.warp(expiry);
    _setSpotPriceAndSubmitForExpiry(2500e18, expiry);

    // Settle Bob ITM first -> increase print
    pcrm.settleAccount(bobAcc);

    // payout is 500 USDC per contract
    int expectedPayout = 500 * amountOfContracts;

    // Positive due to print for Bobs ITM call
    assertEq(cash.netSettledCash(), expectedPayout);
    _assertCashSolvent();

    // Negative due to burn for Alice OTM trade
    pcrm.settleAccount(aliceAcc);
    assertLt(cash.netSettledCash(), 0);
    _assertCashSolvent();

    // Should be 0 after all trades are settled (print for charlie ITM)
    pcrm.settleAccount(charlieAcc);
    assertEq(cash.netSettledCash(), 0);
    _assertCashSolvent();

    assertEq(option.openInterest(callId), 0);
  }

  // Check that negative settled cash (burned) is accounted for in interest rates
  function testInterestRateAtSettleShortCallImbalance() public {
    _createBorrowForUser(charlie, bobAcc, charlieAcc, 500e18);
    _tradeCall();

    uint settlePrint = 500e18;

    // stimulate expiry price
    vm.warp(expiry);
    _setSpotPriceAndSubmitForExpiry(ETH_PRICE + int(settlePrint), expiry);

    // Record interest accrued before settle
    uint interestAccrued =
      _calculateAccruedInterestNoPrint(cash.totalSupply(), cash.totalBorrow(), block.timestamp - cash.lastTimestamp());

    int aliceCashBefore = getCashBalance(aliceAcc);

    // Check that cash was burned to settle
    uint supplyBefore = cash.totalSupply();
    pcrm.settleAccount(aliceAcc);

    // Payout is 500 USDC per contract
    uint expectedPayout = settlePrint * uint(amountOfContracts) / 1e18;

    // $500 * 10 contracts was burned to settle Alice's account
    assertEq(cash.totalSupply() + expectedPayout - interestAccrued, supplyBefore);

    int aliceCashAfter = getCashBalance(aliceAcc);

    // Greater than because interest is paid to Alice's account
    assertGt(aliceCashAfter, aliceCashBefore - int(expectedPayout));

    // We have net burned to Alice's account
    assertEq(cash.netSettledCash(), -int(expectedPayout));
    _assertCashSolvent();

    uint prevBorrow = cash.totalBorrow();

    // Fast forward to check interest rate is including this burned cash
    vm.warp(block.timestamp + 1 weeks);

    // Burned supply which increases interest accrued
    uint interestIgnoringBurned =
      _calculateAccruedInterestNoPrint(cash.totalSupply(), cash.totalBorrow(), block.timestamp - cash.lastTimestamp());
    cash.accrueInterest();

    // Real interest should be less since we account for the "burned" supply
    uint realInterestAccrued = cash.totalBorrow() - prevBorrow;
    assertLt(realInterestAccrued, interestIgnoringBurned);
  }

  function testInterestRateAtSettleShortPutImbalance() public {
    _createBorrowForUser(charlie, bobAcc, charlieAcc, 500e18);
    _tradePut();

    uint settlePrint = 500e18;

    // stimulate expiry price
    vm.warp(expiry);
    _setSpotPriceAndSubmitForExpiry(ETH_PRICE - int(settlePrint), expiry);

    // Record interest accrued before settle
    uint interestAccrued =
      _calculateAccruedInterestNoPrint(cash.totalSupply(), cash.totalBorrow(), block.timestamp - cash.lastTimestamp());

    int aliceCashBefore = getCashBalance(aliceAcc);

    // Check that cash was burned to settle
    uint supplyBefore = cash.totalSupply();
    pcrm.settleAccount(aliceAcc);

    // Payout is 500 USDC per contract
    uint expectedPayout = settlePrint * uint(amountOfContracts) / 1e18;

    // $500 * 10 contracts was burned to settle Alice's account
    assertEq(cash.totalSupply() + expectedPayout - interestAccrued, supplyBefore);

    int aliceCashAfter = getCashBalance(aliceAcc);

    // Greater than because interest is paid to Alice's account
    assertGt(aliceCashAfter, aliceCashBefore - int(expectedPayout));

    // We have net burned to Alice's account
    assertEq(cash.netSettledCash(), -int(expectedPayout));
    _assertCashSolvent();

    uint prevBorrow = cash.totalBorrow();

    // Fast forward to check interest rate is including this burned cash
    vm.warp(block.timestamp + 1 weeks);

    // Burned supply which increases interest accrued
    uint interestIgnoringBurned =
      _calculateAccruedInterestNoPrint(cash.totalSupply(), cash.totalBorrow(), block.timestamp - cash.lastTimestamp());
    cash.accrueInterest();

    // Real interest should be less since we account for the "burned" supply
    uint realInterestAccrued = cash.totalBorrow() - prevBorrow;
    assertLt(realInterestAccrued, interestIgnoringBurned);
  }

  // Check that positive settled cash (minted) is not accounted for in interest rates
  function testInterestRateAtSettleLongCallImbalance() public {
    _createBorrowForUser(charlie, aliceAcc, charlieAcc, 500e18);
    _tradeCall();

    uint settlePrint = 500e18;

    // stimulate expiry price
    vm.warp(expiry);
    _setSpotPriceAndSubmitForExpiry(ETH_PRICE + int(settlePrint), expiry);

    // Record interest accrued before settle
    uint interestAccrued =
      _calculateAccruedInterestNoPrint(cash.totalSupply(), cash.totalBorrow(), block.timestamp - cash.lastTimestamp());

    int bobCashBefore = getCashBalance(bobAcc);

    // Check that cash was printed to settle
    uint supplyBefore = cash.totalSupply();
    pcrm.settleAccount(bobAcc);

    // Payout is 500 USDC per contract
    uint expectedPayout = settlePrint * uint(amountOfContracts) / 1e18;

    // $500 * 10 contracts was printed to settle Bob's account
    assertEq(cash.totalSupply() - expectedPayout - interestAccrued, supplyBefore);

    int bobCashAfter = getCashBalance(bobAcc);

    // Greater than because interest is paid to Bob's account
    assertGt(bobCashAfter, bobCashBefore + int(expectedPayout));

    // We have net print to bob's account
    assertEq(cash.netSettledCash(), int(expectedPayout));
    _assertCashSolvent();

    uint prevBorrow = cash.totalBorrow();

    // Fast forward to check interest rate is not including this printed cash
    vm.warp(block.timestamp + 1 weeks);

    // Interest not accounting for netSettledCash
    interestAccrued =
      _calculateAccruedInterestNoPrint(cash.totalSupply(), cash.totalBorrow(), block.timestamp - cash.lastTimestamp());
    cash.accrueInterest();

    // Real interest should be equal to the interest not accounting for netSettledCash
    uint realInterestAccrued = cash.totalBorrow() - prevBorrow;
    assertEq(realInterestAccrued, interestAccrued);
  }

  function testInterestRateAtSettleLongPutImbalance() public {
    _createBorrowForUser(charlie, aliceAcc, charlieAcc, 500e18);
    _tradePut();

    uint settlePrint = 500e18;

    // stimulate expiry price
    vm.warp(expiry);
    _setSpotPriceAndSubmitForExpiry(ETH_PRICE - int(settlePrint), expiry);

    // Record interest accrued before settle
    uint interestAccrued =
      _calculateAccruedInterestNoPrint(cash.totalSupply(), cash.totalBorrow(), block.timestamp - cash.lastTimestamp());

    int bobCashBefore = getCashBalance(bobAcc);

    // Check that cash was printed to settle
    uint supplyBefore = cash.totalSupply();
    pcrm.settleAccount(bobAcc);

    // Payout is 500 USDC per contract
    uint expectedPayout = settlePrint * uint(amountOfContracts) / 1e18;

    // $500 * 10 contracts was printed to settle Bob's account
    assertEq(cash.totalSupply() - expectedPayout - interestAccrued, supplyBefore);

    int bobCashAfter = getCashBalance(bobAcc);

    // Greater than because interest is paid to Bob's account
    assertGt(bobCashAfter, bobCashBefore + int(expectedPayout));

    // We have net print to bob's account
    assertEq(cash.netSettledCash(), int(expectedPayout));
    _assertCashSolvent();

    uint prevBorrow = cash.totalBorrow();

    // Fast forward to check interest rate not including this printed cash
    vm.warp(block.timestamp + 1 weeks);

    // Interest not accounting for netSettledCash
    interestAccrued =
      _calculateAccruedInterestNoPrint(cash.totalSupply(), cash.totalBorrow(), block.timestamp - cash.lastTimestamp());
    cash.accrueInterest();

    // Real interest should be equal to the interest not accounting for netSettledCash
    uint realInterestAccrued = cash.totalBorrow() - prevBorrow;
    assertEq(realInterestAccrued, interestAccrued);
  }

  ///@dev alice go short, bob go long
  function _tradeCall() public {
    // int premium = 2250e18;
    int premium = 0;
    // alice send call to bob, bob send premium to alice
    _submitTrade(aliceAcc, option, callId, amountOfContracts, bobAcc, cash, 0, premium);
  }

  function _tradePut() public {
    int premium = 1750e18;
    // alice send put to bob, bob send premium to alice
    _submitTrade(aliceAcc, option, putId, amountOfContracts, bobAcc, cash, 0, premium);
  }

  ///@dev create ITM call for user to borrow against
  function _createBorrowForUser(address user, uint fromAcc, uint toAcc, uint borrowAmount) internal {
    _depositCash(alice, aliceAcc, 3000e18);

    // trade ITM call for user to borrow against
    uint callStrike = 100e18;
    _submitTrade(fromAcc, option, uint96(option.getSubId(expiry, callStrike, true)), 1e18, toAcc, cash, 0, 0);
    _withdrawCash(user, toAcc, borrowAmount);
  }

  /**
   * @notice Returns interest accrued for the given parameters.
   * @dev Used to calculate interest without netSettledCash being considered.
   * @param supply the desired supply to test
   * @param borrow the desired borrow to test
   * @param elapsedTime the time elapsed for interest accrual
   */
  function _calculateAccruedInterestNoPrint(uint supply, uint borrow, uint elapsedTime) public view returns (uint) {
    uint borrowRate = rateModel.getBorrowRate(supply, borrow);
    uint borrowInterestFactor = rateModel.getBorrowInterestFactor(elapsedTime, borrowRate);
    uint interestAccrued = borrow.multiplyDecimal(borrowInterestFactor);

    return interestAccrued;
  }
}
