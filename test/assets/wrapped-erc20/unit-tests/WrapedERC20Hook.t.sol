// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "test/shared/mocks/MockERC20.sol";
import "test/shared/mocks/MockManager.sol";

import "src/assets/WrappedERC20Asset.sol";
import "src/Accounts.sol";

contract UNIT_WrappedBaseAssetHook is Test {
  WrappedERC20Asset asset;
  MockERC20 wbtc;
  MockManager manager;

  Accounts accounts;

  uint accId;

  function setUp() public {
    accounts = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    manager = new MockManager(address(accounts));
    wbtc = new MockERC20("WBTC", "WBTC");
    wbtc.setDecimals(8);

    asset = new WrappedERC20Asset(accounts, wbtc);
    accId = accounts.createAccount(address(this), manager);
    asset.setWhitelistManager(address(manager), true);
  }

  function _mintAndDeposit(uint amount) public {
    wbtc.mint(address(this), amount);

    wbtc.approve(address(asset), amount);

    asset.deposit(accId, amount);
  }

  function testDeposit() public {
    _mintAndDeposit(100e8);

    assertEq(wbtc.balanceOf(address(asset)), 100e8);
    assertEq(accounts.getBalance(accId, asset, 0), 100e18); // 18 decimals
  }

  function testCannotWithdrawFromNonOwner() public {
    _mintAndDeposit(100e8);

    vm.prank(address(0xaa));
    vm.expectRevert(IWrappedERC20Asset.WERC_OnlyAccountOwner.selector);
    asset.withdraw(accId, 100e8, address(this));
  }

  function testCanWithdrawFromOwner() public {
    _mintAndDeposit(100e8);

    asset.withdraw(accId, 100e8, address(this));
    assertEq(wbtc.balanceOf(address(this)), 100e8);
    assertEq(wbtc.balanceOf(address(asset)), 0);
    assertEq(accounts.getBalance(accId, asset, 0), 0);
  }

  function testCannotChangeManagerIfExceedCap() public {
    _mintAndDeposit(100e8);

    // create a second manager with less cap
    MockManager manager2 = new MockManager(address(accounts));
    asset.setWhitelistManager(address(manager2), true);
    asset.setOICap(manager2, 1e18);

    vm.expectRevert(IWrappedERC20Asset.WERC_ManagerChangeExceedOICap.selector);
    accounts.changeManager(accId, manager2, "");
  }

  function testCanChangeManagerIfCapIsSafe() public {
    _mintAndDeposit(100e8);

    // create a second manager with less cap
    MockManager manager2 = new MockManager(address(accounts));
    asset.setWhitelistManager(address(manager2), true);

    asset.setOICap(manager2, 100e18);

    accounts.changeManager(accId, manager2, "");
  }
}
