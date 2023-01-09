// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../../../shared/mocks/MockERC20.sol";
import "../../../shared/mocks/MockManager.sol";

import "../../../../src/assets/CashAsset.sol";
import "../../../../src/Accounts.sol";

/**
 * @dev tests for scenarios where insolvent is triggered by the liquidation module
 */
contract UNIT_CashAssetWithdrawFee is Test {
  CashAsset cashAsset;
  MockERC20 usdc;
  MockManager manager;
  Accounts account;
  address liquidationModule = address(0xf00d);

  uint accountId;
  uint depositedAmount;

  function setUp() public {
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    manager = new MockManager(address(account));

    usdc = new MockERC20("USDC", "USDC");

    cashAsset = new CashAsset(account, usdc, liquidationModule);

    cashAsset.setWhitelistManager(address(manager), true);

    depositedAmount = 10000 ether;
    usdc.mint(address(this), depositedAmount);
    usdc.approve(address(cashAsset), type(uint).max);

    accountId = account.createAccount(address(this), manager);

    cashAsset.deposit(accountId, depositedAmount);
  }

  function testCannotTriggerInsolvencyFromAnyone() public {
    vm.expectRevert(ICashAsset.CA_NotLiquidationModule.selector);
    cashAsset.reportLoss(depositedAmount, accountId);
  }

  function testCanTriggerInsolvency() public {
    vm.startPrank(liquidationModule);
    cashAsset.reportLoss(depositedAmount, accountId);
    vm.stopPrank();

    assertEq(cashAsset.temporaryWithdrawFeeEnabled(), true);

    // now 1 cash asset = 0.5 stable (USDC)
    assertEq(cashAsset.toStableExchangeRate(), 0.5e18);
  }

  function testCanDisableWithdrawFeeAfterSystemRecovers() public {
    // trigger insolvency
    vm.prank(liquidationModule);
    cashAsset.reportLoss(depositedAmount, accountId);

    // some people donate USDC to the cashAsset contract
    usdc.mint(address(cashAsset), depositedAmount);

    // disable withdraw fee
    cashAsset.disableWithdrawFee();

    assertEq(cashAsset.temporaryWithdrawFeeEnabled(), false);
  }
}
