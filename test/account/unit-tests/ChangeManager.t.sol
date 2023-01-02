// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../../../src/interfaces/IAccounts.sol";
import "../../../src/Account.sol";

import {MockManager} from "../../shared/mocks/MockManager.sol";
import {MockAsset} from "../../shared/mocks/MockAsset.sol";

import {AccountTestBase} from "./AccountTestBase.sol";

contract UNIT_ChangeManager is Test, AccountTestBase {
  error MockError();

  MockManager newManager;

  function setUp() public {
    setUpAccounts();

    newManager = new MockManager(address(account));
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
    vm.expectRevert(abi.encodeWithSelector(IAccounts.AC_CannotChangeToSameManager.selector, alice, aliceAcc));
    account.changeManager(aliceAcc, dumbManager, "");
    vm.stopPrank();
  }

  function testMigrationShouldNotMakeDuplicatedCallToAssets() public {
    MockAsset mockOptionAsset = new MockAsset(coolToken, IAccounts(address(account)), true); // allow negative balance
    vm.label(address(mockOptionAsset), "DumbOption");

    // create another account just to transfer assets
    uint newAccount1 = account.createAccount(address(this), dumbManager);

    // create new account and grant access to this contract to adjust balance
    uint accountToTest = account.createAccount(alice, dumbManager);
    vm.startPrank(alice);
    account.setApprovalForAll(address(this), true);
    vm.stopPrank();

    // adjust asset balances so new account has multiple balances
    // adjust usdc token balance
    mintAndDeposit(alice, accountToTest, usdc, usdcAsset, 0, 1e18);

    // adjust option token balances
    (uint subId1, uint subId2) = (1, 2);
    (int amount1, int amount2) = (1e18, -2e18);
    transferToken(newAccount1, accountToTest, mockOptionAsset, subId1, amount1);
    transferToken(newAccount1, accountToTest, mockOptionAsset, subId2, amount2);

    // start recording calls to optionAsset
    mockOptionAsset.setRecordManagerChangeCalls(true);
    usdcAsset.setRecordManagerChangeCalls(true);

    vm.startPrank(alice);
    account.changeManager(accountToTest, newManager, "");
    vm.stopPrank();

    assertEq(mockOptionAsset.handleManagerCalled(), 1);
    assertEq(usdcAsset.handleManagerCalled(), 1);
  }
}
