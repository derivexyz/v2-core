// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../../../src/interfaces/IAccount.sol";

import {DumbManager} from "../../mocks/managers/DumbManager.sol";

import {AccountTestBase} from "./AccountTestBase.sol";

contract UNIT_ChangeManager is Test, AccountTestBase {
  
  error MockError();

  DumbManager newManager;

  function setUp() public {
    setUpAccounts();

    newManager = new DumbManager(address(account));
  }

  function testCanMigrateIfOldManagerAgree() public {    
    vm.prank(alice);
    // expect call to old manager
    vm.expectCall(address(dumbManager), abi.encodeCall(dumbManager.handleManagerChange, (aliceAcc, newManager)));
    account.changeManager(aliceAcc, newManager, "");
    vm.stopPrank();
    
    // manager is updated
    assertEq(address(account.manager(aliceAcc)), address(newManager));
  }

  function testCannotMigrateIfOldManagerDisagree() public { 
    dumbManager.setRevertHandleManager(true);
    vm.prank(alice);
    vm.expectRevert();
    account.changeManager(aliceAcc, newManager, "");
    vm.stopPrank();
    vm.clearMockedCalls();
  }

  function testCannotChangeToSameManager() public {
    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(IAccount.CannotChangeToSameManager.selector, 
        address(account), 
        alice,
        aliceAcc
      ));
    account.changeManager(aliceAcc, dumbManager, "");
    vm.stopPrank();
  }

  function testMigrationShouldNotMakeDuplicatedCallToAssets() public { 
    
  }

}