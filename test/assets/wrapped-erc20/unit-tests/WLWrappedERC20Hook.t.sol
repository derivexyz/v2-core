// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "test/shared/mocks/MockERC20.sol";
import "test/shared/mocks/MockManager.sol";
import {IPositionTracking} from "../../../../src/interfaces/IPositionTracking.sol";
import {IAllowances} from "../../../../src/interfaces/IAllowances.sol";
import "../../../../src/assets/WLWrappedERC20Asset.sol";
import "../../../../src/SubAccounts.sol";

contract UNIT_WLWrappedBaseAssetHook is Test {
  WLWrappedERC20Asset asset;
  MockERC20 wbtc;
  MockManager manager;

  SubAccounts subAccounts;

  uint accId1;
  uint accId2;

  function setUp() public {
    subAccounts = new SubAccounts("Lyra Margin Accounts", "LyraMarginNFTs");

    manager = new MockManager(address(subAccounts));
    wbtc = new MockERC20("WBTC", "WBTC");
    wbtc.setDecimals(8);

    asset = new WLWrappedERC20Asset(subAccounts, wbtc);
    accId1 = subAccounts.createAccount(address(this), manager);
    accId2 = subAccounts.createAccount(address(this), manager);
    asset.setWhitelistManager(address(manager), true);

    wbtc.mint(address(this), 1000e8);
    wbtc.approve(address(asset), 1000e8);
  }

  function _mintAndDeposit(uint amount) public {}

  function testDeposit() public {
    vm.expectRevert(WLWrappedERC20Asset.WLWERC_NotWhitelisted.selector);
    asset.deposit(accId1, 100e8);

    asset.setSubAccountWL(accId1, true);

    // only acc1 can deposit now
    asset.deposit(accId1, 100e8);

    assertEq(wbtc.balanceOf(address(asset)), 100e8);
    assertEq(subAccounts.getBalance(accId1, asset, 0), 100e18); // 18 decimals

    vm.expectRevert(WLWrappedERC20Asset.WLWERC_NotWhitelisted.selector);
    asset.deposit(accId2, 100e8);

    // now enable it for anyone
    asset.setWhitelistEnabled(false);
    asset.deposit(accId2, 100e8);

    assertEq(wbtc.balanceOf(address(asset)), 200e8);
    assertEq(subAccounts.getBalance(accId2, asset, 0), 100e18); // 18 decimals
  }
}
