// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../../../shared/mocks/MockERC20.sol";
import "../../../shared/mocks/MockManager.sol";

import "../../../../src/assets/CashAsset.sol";

contract UNIT_CashAssetHook is Test {
  CashAsset cashAsset;
  MockERC20 usdc;
  MockManager manager;
  address account;

  function setUp() public {
    account = address(0xaa);

    manager = new MockManager(account);
    usdc = new MockERC20("USDC", "USDC");

    cashAsset = new CashAsset(account, address(usdc));
  }

  function testCannotCallHandleAdjustmentFromNonAccount() public {
    vm.expectRevert(CashAsset.LA_NotAccount.selector);
    AccountStructs.AssetAdjustment memory adjustment = AccountStructs.AssetAdjustment(0, cashAsset, 0, 0, 0x00);
    cashAsset.handleAdjustment(adjustment, 0, manager, address(this));
  }

  function testCannotExecuteHandleAdjustmentIfManagerIsNotWhitelisted() public {
    /* this could happen if someone is trying to transfer our cash asset to an account controlled by malicious manager */
    AccountStructs.AssetAdjustment memory adjustment = AccountStructs.AssetAdjustment(0, cashAsset, 0, 0, 0x00);
    vm.expectRevert(CashAsset.LA_UnknownManager.selector);

    vm.prank(account);
    cashAsset.handleAdjustment(adjustment, 0, manager, address(this));
  }

  function testAssetHookAccurInterestOnPositiveAdjustment() public {
    cashAsset.setWhitelistManager(address(manager), true);
    int delta = 100;
    AccountStructs.AssetAdjustment memory adjustment = AccountStructs.AssetAdjustment(0, cashAsset, 0, delta, 0x00);

    vm.prank(account);
    (int postBalance, bool needAllowance) = cashAsset.handleAdjustment(adjustment, 0, manager, address(this));

    assertEq(cashAsset.lastTimestamp(), block.timestamp);
    assertEq(needAllowance, false);
    // todo: updaete this check to include interest
    assertEq(postBalance, delta);
  }

  function testAssetHookAccurInterestOnNegativeAdjustment() public {
    cashAsset.setWhitelistManager(address(manager), true);
    int delta = -100;
    AccountStructs.AssetAdjustment memory adjustment = AccountStructs.AssetAdjustment(0, cashAsset, 0, delta, 0x00);

    // stimulate call from account
    vm.prank(account);
    (int postBalance, bool needAllowance) = cashAsset.handleAdjustment(adjustment, 0, manager, address(this));

    assertEq(needAllowance, true);
    // todo: updaete this check to include interest
    assertEq(postBalance, delta);
  }

  function testChangeManagerHookRevertOnNonWhitelistedManager() public {
    vm.expectRevert(CashAsset.LA_UnknownManager.selector);

    vm.prank(account);
    cashAsset.handleManagerChange(0, manager);
  }

  function testWillNotRevertOnLegalManagerUpdate() public {
    cashAsset.setWhitelistManager(address(manager), true);

    vm.prank(account);
    cashAsset.handleManagerChange(0, manager);
  }
}
