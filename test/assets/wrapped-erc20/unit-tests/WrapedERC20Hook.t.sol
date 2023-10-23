// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "test/shared/mocks/MockERC20.sol";
import "test/shared/mocks/MockManager.sol";
import {IPositionTracking} from "../../../../src/interfaces/IPositionTracking.sol";
import {IAllowances} from "../../../../src/interfaces/IAllowances.sol";
import "../../../../src/assets/WrappedERC20Asset.sol";
import "../../../../src/SubAccounts.sol";

contract UNIT_WrappedBaseAssetHook is Test {
  WrappedERC20Asset asset;
  MockERC20 wbtc;
  MockManager manager;

  SubAccounts subAccounts;

  uint accId;

  function setUp() public {
    subAccounts = new SubAccounts("Lyra Margin Accounts", "LyraMarginNFTs");

    manager = new MockManager(address(subAccounts));
    wbtc = new MockERC20("WBTC", "WBTC");
    wbtc.setDecimals(8);

    asset = new WrappedERC20Asset(subAccounts, wbtc);
    accId = subAccounts.createAccount(address(this), manager);
    asset.setWhitelistManager(address(manager), true);
  }

  function _mintAndDeposit(uint amount) public {
    wbtc.mint(address(this), amount);

    wbtc.approve(address(asset), amount);

    asset.deposit(accId, amount);
  }

  function testRevertsForInvalidSubId() public {
    uint accId2 = subAccounts.createAccount(address(this), manager);

    ISubAccounts.AssetTransfer memory transfer =
      ISubAccounts.AssetTransfer({fromAcc: accId, toAcc: accId2, asset: asset, subId: 1, amount: 1e18, assetData: ""});
    vm.expectRevert(IWrappedERC20Asset.WERC_InvalidSubId.selector);
    subAccounts.submitTransfer(transfer, "");
  }

  function testDeposit() public {
    _mintAndDeposit(100e8);

    assertEq(wbtc.balanceOf(address(asset)), 100e8);
    assertEq(subAccounts.getBalance(accId, asset, 0), 100e18); // 18 decimals
  }

  function testCanDepositZero() public {
    _mintAndDeposit(0);
  }

  function testCannotHaveNegativeBalance() public {
    uint accId2 = subAccounts.createAccount(address(this), manager);

    ISubAccounts.AssetTransfer memory transfer =
      ISubAccounts.AssetTransfer({fromAcc: accId, toAcc: accId2, asset: asset, subId: 0, amount: 1e18, assetData: ""});
    vm.expectRevert(IWrappedERC20Asset.WERC_CannotBeNegative.selector);
    subAccounts.submitTransfer(transfer, "");
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
    assertEq(subAccounts.getBalance(accId, asset, 0), 0);
  }

  function testCannotChangeManagerIfExceedCap() public {
    _mintAndDeposit(100e8);

    // create a second manager with less cap
    MockManager manager2 = new MockManager(address(subAccounts));
    asset.setWhitelistManager(address(manager2), true);
    asset.setTotalPositionCap(manager2, 1e18);

    vm.expectRevert(IPositionTracking.PT_CapExceeded.selector);
    subAccounts.changeManager(accId, manager2, "");
  }

  function testCanChangeManagerIfCapIsSafe() public {
    _mintAndDeposit(100e8);

    // create a second manager with less cap
    MockManager manager2 = new MockManager(address(subAccounts));
    asset.setWhitelistManager(address(manager2), true);

    asset.setTotalPositionCap(manager2, 100e18);

    subAccounts.changeManager(accId, manager2, "");
  }

  function testCannotTransferPositiveBalanceWithoutApproval() public {
    _mintAndDeposit(100e8);

    uint aliceAcc = subAccounts.createAccount(address(0xaa), manager);
    // cannot transfer to alice
    ISubAccounts.AssetTransfer memory assetTransfer =
      ISubAccounts.AssetTransfer({fromAcc: accId, toAcc: aliceAcc, asset: asset, subId: 0, amount: 1e18, assetData: ""});

    vm.expectRevert(
      abi.encodeWithSelector(IAllowances.NotEnoughSubIdOrAssetAllowances.selector, address(this), aliceAcc, 1e18, 0, 0)
    );
    subAccounts.submitTransfer(assetTransfer, "");
  }
}
