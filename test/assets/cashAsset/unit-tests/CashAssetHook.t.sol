// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../../../shared/mocks/MockERC20.sol";
import "../../../shared/mocks/MockManager.sol";

import "../../../../src/assets/CashAsset.sol";
import {ISubAccounts} from "../../../../src/interfaces/ISubAccounts.sol";
import {ICashAsset} from "../../../../src/interfaces/ICashAsset.sol";
import {IManagerWhitelist} from "../../../../src/interfaces/IManagerWhitelist.sol";
import "../mocks/MockInterestRateModel.sol";

contract UNIT_CashAssetHook is Test {
  CashAsset cashAsset;
  MockERC20 usdc;
  MockManager manager;
  IInterestRateModel rateModel;
  address account;

  function setUp() public {
    account = address(0xaa);

    manager = new MockManager(account);
    usdc = new MockERC20("USDC", "USDC");

    rateModel = new MockInterestRateModel(0.5 * 1e18);
    cashAsset = new CashAsset(ISubAccounts(account), usdc, rateModel);
  }

  function testCannotCallHandleAdjustmentFromNonAccount() public {
    vm.expectRevert(IManagerWhitelist.MW_OnlyAccounts.selector);
    ISubAccounts.AssetAdjustment memory adjustment = ISubAccounts.AssetAdjustment(0, cashAsset, 0, 0, 0x00);
    cashAsset.handleAdjustment(adjustment, 0, 0, manager, address(this));
  }

  function testCannotExecuteHandleAdjustmentIfManagerIsNotWhitelisted() public {
    /* this could happen if someone is trying to transfer our cash asset to an account controlled by malicious manager */
    ISubAccounts.AssetAdjustment memory adjustment = ISubAccounts.AssetAdjustment(0, cashAsset, 0, 0, 0x00);
    vm.expectRevert(IManagerWhitelist.MW_UnknownManager.selector);

    vm.prank(account);
    cashAsset.handleAdjustment(adjustment, 0, 0, manager, address(this));
  }

  function testAssetHookAccurInterestOnPositiveAdjustment() public {
    cashAsset.setWhitelistManager(address(manager), true);
    int delta = 100;
    ISubAccounts.AssetAdjustment memory adjustment = ISubAccounts.AssetAdjustment(0, cashAsset, 0, delta, 0x00);

    vm.prank(account);
    (int postBalance, bool needAllowance) = cashAsset.handleAdjustment(adjustment, 0, 0, manager, address(this));

    assertEq(cashAsset.lastTimestamp(), block.timestamp);
    assertEq(needAllowance, false);
    // todo: updaete this check to include interest
    assertEq(postBalance, delta);
  }

  function testAssetHookAccurInterestOnNegativeAdjustment() public {
    cashAsset.setWhitelistManager(address(manager), true);
    int delta = -100;
    ISubAccounts.AssetAdjustment memory adjustment = ISubAccounts.AssetAdjustment(0, cashAsset, 0, delta, 0x00);

    // stimulate call from account
    vm.prank(account);
    (int postBalance, bool needAllowance) = cashAsset.handleAdjustment(adjustment, 0, 0, manager, address(this));

    assertEq(needAllowance, true);
    // todo: updaete this check to include interest
    assertEq(postBalance, delta);
  }

  function testChangeManagerHookRevertOnNonWhitelistedManager() public {
    vm.expectRevert(IManagerWhitelist.MW_UnknownManager.selector);

    vm.prank(account);
    cashAsset.handleManagerChange(0, manager);
  }

  function testWillNotRevertOnLegalManagerUpdate() public {
    cashAsset.setWhitelistManager(address(manager), true);

    vm.prank(account);
    cashAsset.handleManagerChange(0, manager);
  }
}
