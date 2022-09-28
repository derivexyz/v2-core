// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../../../src/interfaces/IAccount.sol";

import {DumbManager} from "../../mocks/managers/DumbManager.sol";
import {DumbAsset} from "../../mocks/assets/DumbAsset.sol";

import {AccountTestBase} from "./AccountTestBase.sol";

contract UNIT_ChangeManager is Test, AccountTestBase {
  
  error MockError();

  DumbManager newManager;

  function setUp() public {
    setUpAccounts();

    newManager = new DumbManager(address(account));
    vm.label(address(newManager), "NewManager");
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

  function testCannotMigrateIfAssetDisagree() public { 
    dumbManager.setRevertHandleManager(true);
    // alice has usdc in her wallet
    usdcAsset.setRevertHandleManagerChange(true);
    
    vm.prank(alice);
    vm.expectRevert();
    account.changeManager(aliceAcc, newManager, "");
    vm.stopPrank();
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
    DumbAsset mockOptionAsset = new DumbAsset(coolToken, account, true); // allow negative balance
    vm.label(address(mockOptionAsset), "DumbOption");

    // create new account and grant access to this contract to adjust balance
    uint newAccount1 = account.createAccount(address(this), dumbManager);
    uint newAccount2 = account.createAccount(alice, dumbManager);
    vm.startPrank(alice);
    account.setApprovalForAll(address(this), true);
    vm.stopPrank();

    // adjust balance so new account has multiple balances with mockOptionAsset
    (uint subId1, uint subId2) = (1, 2);
    (int amount1, int amount2) = (1e18, 2e18);
    transferToken(newAccount1, newAccount2, mockOptionAsset, subId1, amount1);
    transferToken(newAccount1, newAccount2, mockOptionAsset, subId2, amount2);

    // start recording calls to optionAsset
    mockOptionAsset.setRecordManagerChangeCalls(true);
    vm.startPrank(alice);
    account.changeManager(newAccount2, newManager, "");
    assertEq(mockOptionAsset.handleManagerCalled(), 1);
    vm.stopPrank();
  }

}