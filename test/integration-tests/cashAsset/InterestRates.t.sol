// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../shared/IntegrationTestBase.sol";
import "src/interfaces/IManager.sol";

/**
 * @dev testing charge of OI fee in a real setting
 */
contract INTEGRATION_InterestRatesTest is IntegrationTestBase {
  address alice = address(0xace);
  address bob = address(0xb0b);
  address charlie = address(0xca1e);
  uint aliceAcc;
  uint bobAcc;
  uint charlieAcc;

  function setUp() public {
    _setupIntegrationTestComplete();

    vm.prank(alice);
    accounts.setApprovalForAll(address(this), true);

    vm.prank(bob);
    accounts.setApprovalForAll(address(this), true);
    
    vm.prank(charlie);
    accounts.setApprovalForAll(address(this), true);
  }

  function testBorrowAgainstITMCall() public {
    // Alice and Bob deposit cash into the system
    aliceAcc = accounts.createAccount(alice, pcrm);
    _depositCash(address(alice), aliceAcc, DEFAULT_DEPOSIT);

    bobAcc = accounts.createAccount(bob, pcrm);
    _depositCash(address(bob), bobAcc, DEFAULT_DEPOSIT);

    charlieAcc = accounts.createAccount(charlie, pcrm);

    // Charlie borrows money against his ITM Call
    uint callExpiry = block.timestamp + 4 weeks;
    uint callStrike = 200e8;
    uint callId = option.getSubId(callExpiry, callStrike, true);

    _submitTrade(aliceAcc, option, uint96(callId), 1e18, charlieAcc, cash, 0, 0);
    
    assertEq(cash.borrowIndex(), 1e18);
    assertEq(cash.supplyIndex(), 1e18);

    // Borrow against the option
    _withdrawCash(charlie, charlieAcc, 500e18);

    console2.log("Charlie", accounts.getBalance(charlieAcc, cash, 0));
    // Charlie balance should be negative
    assertLt(accounts.getBalance(charlieAcc, cash, 0), 0);

    vm.warp(block.timestamp + 1 weeks);
    cash.accrueInterest();

    assertGt(cash.borrowIndex(), 1e18);
    assertGt(cash.supplyIndex(), 1e18);
  }

  // function testCannotBorrowAgainstOTMCall() public {
  //   // Alice and Bob deposit cash into the system
  //   aliceAcc = accounts.createAccount(alice, pcrm);
  //   _depositCash(address(alice), aliceAcc, DEFAULT_DEPOSIT);

  //   bobAcc = accounts.createAccount(bob, pcrm);
  //   _depositCash(address(bob), bobAcc, DEFAULT_DEPOSIT);

  //   charlieAcc = accounts.createAccount(charlie, pcrm);

  //   // OTM Call
  //   uint callExpiry = block.timestamp + 1;
  //   uint callStrike = 5000e8;
  //   uint callId = option.getSubId(callExpiry, callStrike, true);

  //    _submitTrade(aliceAcc, option, uint96(callId), 1e18, charlieAcc, cash, 0, 50e18);
    
  //   assertEq(cash.borrowIndex(), 1e18);
  //   assertEq(cash.supplyIndex(), 1e18);

  //   // Fails to borrow against the OTM call
  //    vm.expectRevert(abi.encodeWithSelector(PCRM.PCRM_MarginRequirementNotMet.selector,-500e18));
  //   _withdrawCash(charlie, charlieAcc, 500e18);
  // }

  function testBorrowAgainstITMPut() public {
    // Alice and Bob deposit cash into the system
    aliceAcc = accounts.createAccount(alice, pcrm);
    _depositCash(address(alice), aliceAcc, DEFAULT_DEPOSIT);

    bobAcc = accounts.createAccount(bob, pcrm);
    _depositCash(address(bob), bobAcc, DEFAULT_DEPOSIT);

    charlieAcc = accounts.createAccount(charlie, pcrm);

    // Charlie borrows money against his ITM Put
    uint putExpiry = block.timestamp + 4 weeks;
    uint putStrike = 7000e8;
    uint96 putId = option.getSubId(putExpiry, putStrike, true);

    _submitTrade(aliceAcc, option, putId, 1e18, charlieAcc, cash, 0, 50e18);
    
    assertEq(cash.borrowIndex(), 1e18);
    assertEq(cash.supplyIndex(), 1e18);

    // Borrow against the option
    _withdrawCash(charlie, charlieAcc, 50e18);

    // Charlie balance should be -1000
    assertLt(accounts.getBalance(charlieAcc, cash, 0), 0);

    vm.warp(block.timestamp + 1 weeks);
    cash.accrueInterest();

    assertGt(cash.borrowIndex(), 1e18);
    assertGt(cash.supplyIndex(), 1e18);
  }
}
