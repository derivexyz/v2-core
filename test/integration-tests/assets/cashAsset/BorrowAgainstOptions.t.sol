//// SPDX-License-Identifier: UNLICENSED
//pragma solidity ^0.8.18;
//
//import "forge-std/Test.sol";
//import "forge-std/console2.sol";
//
//import "../../shared/IntegrationTestBase.sol";
//import {IManager} from "src/interfaces/IManager.sol";
//
///**
// * @dev testing charge of OI fee in a real setting
// */
//contract INTEGRATION_BorrowAgainstOptionsTest is IntegrationTestBase {
//  using DecimalMath for uint;
//
//  address charlie = address(0xca1e);
//  uint charlieAcc;
//
//  function setUp() public {
//    _setupIntegrationTestComplete();
//
//    vm.prank(charlie);
//    accounts.setApprovalForAll(address(this), true);
//  }
//
//  function testBorrowAgainstITMCall() public {
//    // Alice and Bob deposit cash into the system
//    _depositCash(address(alice), aliceAcc, DEFAULT_DEPOSIT);
//    _depositCash(address(bob), bobAcc, DEFAULT_DEPOSIT);
//
//    charlieAcc = accounts.createAccount(charlie, pcrm);
//
//    // Charlie borrows money against his ITM Call
//    uint callExpiry = block.timestamp + 4 weeks;
//    uint callStrike = 200e18;
//    uint callId = option.getSubId(callExpiry, callStrike, true);
//
//    _submitTrade(aliceAcc, option, uint96(callId), 1e18, charlieAcc, cash, 0, 0);
//
//    assertEq(cash.borrowIndex(), 1e18);
//    assertEq(cash.supplyIndex(), 1e18);
//
//    // Borrow against the option
//    uint borrowAmount = 500e18;
//    _withdrawCash(charlie, charlieAcc, borrowAmount);
//
//    uint oiFee = pcrm.OIFeeRateBPS().multiplyDecimal(_getForwardPrice(callExpiry));
//
//    // Charlie balance should be negative
//    assertEq(getCashBalance(charlieAcc), -int(borrowAmount + oiFee));
//
//    vm.warp(block.timestamp + 1 weeks);
//    _setSpotPriceE18(2000e18); // after 1 week jump, need to set time again otherwise it revert with "Stale Spot"
//
//    cash.accrueInterest();
//    assertEq(cash.borrowIndex(), 1001344096864415691);
//    assertEq(cash.supplyIndex(), 1000067460170559555);
//  }
//
//  function testCannotBorrowAgainstOTMCall() public {
//    // Alice and Bob deposit cash into the system
//    _depositCash(address(alice), aliceAcc, DEFAULT_DEPOSIT);
//    _depositCash(address(bob), bobAcc, DEFAULT_DEPOSIT);
//
//    charlieAcc = accounts.createAccount(charlie, pcrm);
//    _depositCash(address(charlie), charlieAcc, 2e18); // deposit $2 to pay init OI fee
//    _depositCash(address(charlie), charlieAcc, 50e18); // deposit $50 for min offset
//
//    // OTM Call
//    uint callExpiry = block.timestamp + 1;
//    uint callStrike = 4000e18;
//    uint callId = option.getSubId(callExpiry, callStrike, true);
//
//    // charlie pays 0 for the call
//    _submitTrade(aliceAcc, option, uint96(callId), 1e18, charlieAcc, cash, 0, 0);
//
//    // Fails to borrow against the OTM call (charlie now has net init margin == 0)
//    vm.expectRevert(abi.encodeWithSelector(PCRM.PCRM_MarginRequirementNotMet.selector, -10e18));
//    _withdrawCash(charlie, charlieAcc, 10e18);
//  }
//
//  function testBorrowAgainstITMPut() public {
//    // Alice and Bob deposit cash into the system
//    _depositCash(address(alice), aliceAcc, DEFAULT_DEPOSIT);
//    _depositCash(address(bob), bobAcc, DEFAULT_DEPOSIT);
//
//    charlieAcc = accounts.createAccount(charlie, pcrm);
//
//    // Charlie borrows money against his ITM Put
//    uint putExpiry = block.timestamp + 4 weeks;
//    uint putStrike = 3000e18;
//    uint96 putId = option.getSubId(putExpiry, putStrike, false);
//
//    _submitTrade(aliceAcc, option, putId, 1e18, charlieAcc, cash, 0, 0);
//
//    assertEq(cash.borrowIndex(), 1e18);
//    assertEq(cash.supplyIndex(), 1e18);
//
//    // Borrow against the option
//    _withdrawCash(charlie, charlieAcc, 50e18);
//
//    // Charlie balance should be -borrowed amount + oiFee
//    uint oiFee = pcrm.OIFeeRateBPS().multiplyDecimal(_getForwardPrice(putExpiry));
//    assertEq(accounts.getBalance(charlieAcc, cash, 0), -int(50e18 + oiFee));
//
//    vm.warp(block.timestamp + 1 weeks);
//    cash.accrueInterest();
//
//    assertEq(cash.borrowIndex(), 1001171311598975475);
//    assertEq(cash.supplyIndex(), 1000006089602394193);
//  }
//
//  function testCannotBorrowAgainstOTMPut() public {
//    // Alice and Bob deposit cash into the system
//    _depositCash(address(alice), aliceAcc, DEFAULT_DEPOSIT);
//    _depositCash(address(bob), bobAcc, DEFAULT_DEPOSIT);
//
//    charlieAcc = accounts.createAccount(charlie, pcrm);
//    _depositCash(address(charlie), charlieAcc, 2e18); // deposit $2 to pay init OI fee
//    _depositCash(address(charlie), charlieAcc, 50e18); // deposit $50 to pay init OI fee
//
//    // OTM Put
//    uint putExpiry = block.timestamp + 1;
//    uint putStrike = 200e18;
//    uint putId = option.getSubId(putExpiry, putStrike, false);
//
//    // charlie pays 0 for the put
//    _submitTrade(aliceAcc, option, uint96(putId), 1e18, charlieAcc, cash, 0, 0);
//
//    // Fails to borrow against the OTM put (charlie now has net init margin == 0)
//    vm.expectRevert(abi.encodeWithSelector(PCRM.PCRM_MarginRequirementNotMet.selector, -10e18));
//    _withdrawCash(charlie, charlieAcc, 10e18);
//  }
//}
