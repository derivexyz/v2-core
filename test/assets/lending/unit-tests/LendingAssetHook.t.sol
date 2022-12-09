// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../../../shared/mocks/MockERC20.sol";
import "../../../shared/mocks/MockManager.sol";

import "../../../../src/assets/Lending.sol";

contract UNIT_LendingAssetHook is Test {
  Lending lending;
  MockERC20 usdc;
  MockManager manager;
  address account;

  function setUp() public {
    account = address(0xaa);

    manager = new MockManager(account);
    usdc = new MockERC20("USDC", "USDC");

    lending = new Lending(account, address(usdc));
  }

  function testCannotCallHandleAdjustmentFromNonAccount() public {
    vm.expectRevert(Lending.LA_NotAccount.selector);
    AccountStructs.AssetAdjustment memory adjustment = AccountStructs.AssetAdjustment(0, lending, 0, 0, 0x00);
    lending.handleAdjustment(adjustment, 0, manager, address(this));
  }

  function testCannotExecuteHandleAdjustmentIfManagerIsNotWhitelisted() public {
    /* this could happen if someone is trying to transfer our cash asset to an account controlled by malicious manager */
    AccountStructs.AssetAdjustment memory adjustment = AccountStructs.AssetAdjustment(0, lending, 0, 0, 0x00);
    vm.expectRevert(Lending.LA_UnknownManager.selector);

    vm.prank(account);
    lending.handleAdjustment(adjustment, 0, manager, address(this));
  }

  function testAssetHookAccurInterestOnPositiveAdjustment() public {
    lending.setWhitelistManager(address(manager), true);
    int delta = 100;
    AccountStructs.AssetAdjustment memory adjustment = AccountStructs.AssetAdjustment(0, lending, 0, delta, 0x00);

    vm.prank(account);
    (int postBalance, bool needAllowance) = lending.handleAdjustment(adjustment, 0, manager, address(this));

    assertEq(lending.lastTimestamp(), block.timestamp);
    assertEq(needAllowance, false);
    // todo: updaete this check to include interest
    assertEq(postBalance, delta);
  }

  function testAssetHookAccurInterestOnNegativeAdjustment() public {
    lending.setWhitelistManager(address(manager), true);
    int delta = -100;
    AccountStructs.AssetAdjustment memory adjustment = AccountStructs.AssetAdjustment(0, lending, 0, delta, 0x00);

    // stimulate call from account
    vm.prank(account);
    (int postBalance, bool needAllowance) = lending.handleAdjustment(adjustment, 0, manager, address(this));

    assertEq(needAllowance, true);
    // todo: updaete this check to include interest
    assertEq(postBalance, delta);
  }

  function testChangeManagerHookRevertOnNonWhitelistedManager() public {
    vm.expectRevert(Lending.LA_UnknownManager.selector);

    vm.prank(account);
    lending.handleManagerChange(0, manager);
  }

  function testWillNotRevertOnLegalManagerUpdate() public {
    lending.setWhitelistManager(address(manager), true);

    vm.prank(account);
    lending.handleManagerChange(0, manager);
  }
}
