// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../../shared/mocks/MockERC20.sol";
import "../../../shared/mocks/MockManager.sol";
import "../mocks/MockInterestRateModel.sol";
import "../../../../src/assets/CashAsset.sol";
import "../../../../src/Accounts.sol";

/**
 * @dev tests for scenarios where insolvent is triggered by the liquidation module
 */
contract UNIT_CashAssetWithdrawFee is Test {
  CashAsset cashAsset;
  MockERC20 usdc;
  MockManager manager;
  Accounts accounts;
  IInterestRateModel rateModel;
  address liquidationModule = address(0xf00d);

  uint accountId;
  uint depositedAmount;

  function setUp() public {
    accounts = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    manager = new MockManager(address(accounts));

    usdc = new MockERC20("USDC", "USDC");

    rateModel = new MockInterestRateModel(1e18);
    cashAsset = new CashAsset(accounts, usdc, rateModel, 0, liquidationModule);

    cashAsset.setWhitelistManager(address(manager), true);

    depositedAmount = 10000 ether;
    usdc.mint(address(this), depositedAmount);
    usdc.approve(address(cashAsset), type(uint).max);

    accountId = accounts.createAccount(address(this), manager);

    cashAsset.deposit(accountId, depositedAmount);

    assertEq(cashAsset.getCashToStableExchangeRate(), 1e18);
  }

  function testCannotTriggerInsolvencyFromAnyone() public {
    vm.expectRevert(ICashAsset.CA_NotLiquidationModule.selector);
    cashAsset.socializeLoss(depositedAmount, accountId);
  }

  function testCanTriggerInsolvency() public {
    vm.startPrank(liquidationModule);
    cashAsset.socializeLoss(depositedAmount, accountId);
    vm.stopPrank();

    assertEq(cashAsset.temporaryWithdrawFeeEnabled(), true);

    // now 1 cash asset = 0.5 stable (USDC)
    assertEq(cashAsset.getCashToStableExchangeRate(), 0.5e18);
  }

  function testFeeIsAppliedToWithdrawAfterEnables() public {
    vm.startPrank(liquidationModule);
    // loss is 25% of the pool
    // meaning 1 cash is worth only 0.8% USDC after solcializing the loss
    cashAsset.socializeLoss(depositedAmount / 4, accountId);
    vm.stopPrank();

    assertEq(cashAsset.temporaryWithdrawFeeEnabled(), true);
    assertEq(cashAsset.getCashToStableExchangeRate(), 0.8e18);

    uint amountUSDCToWithdraw = 100e18;
    int cashBalanceBefore = accounts.getBalance(accountId, cashAsset, 0);
    cashAsset.withdraw(accountId, amountUSDCToWithdraw, address(this));
    int cashBalanceAfter = accounts.getBalance(accountId, cashAsset, 0);

    // needs to burn 125 cash to get 100 USDC outf
    assertEq(cashBalanceBefore - cashBalanceAfter, 125e18);
  }

  function testCanDisableWithdrawFeeAfterSystemRecovers() public {
    uint smFeeCut = 0.5 * 1e18;
    cashAsset.setSmFee(smFeeCut);
    // trigger insolvency
    vm.prank(liquidationModule);
    cashAsset.socializeLoss(depositedAmount, accountId);

    // SM fee set to 100%
    assertEq(cashAsset.smFeePercentage(), DecimalMath.UNIT);
    // some people donate USDC to the cashAsset contract
    usdc.mint(address(cashAsset), depositedAmount);

    // disable withdraw fee
    cashAsset.disableWithdrawFee();

    assertEq(cashAsset.smFeePercentage(), smFeeCut);
    assertEq(cashAsset.temporaryWithdrawFeeEnabled(), false);
  }

  function testSmFeeCanCoverInsolvency() public {
    uint smFeeCut = 1e18;
    cashAsset.setSmFee(smFeeCut);

    uint newAccount = accounts.createAccount(address(this), manager);
    uint totalBorrow = cashAsset.totalBorrow();
    assertEq(totalBorrow, 0);

    // Increase total borrow amount
    uint requiredAmount = 1000 * 1e18;
    cashAsset.withdraw(newAccount, requiredAmount, address(this));

    vm.warp(block.timestamp + 1 weeks);
    cashAsset.accrueInterest();

    // Assert for sm fees
    assertEq(cashAsset.accruedSmFees(), requiredAmount / 2);

    // trigger insolvency
    int preBalance = accounts.getBalance(accountId, cashAsset, 0);
    console.log(" --- Pre balance is --- ");
    console.logInt(preBalance);
    console.log(requiredAmount / 2);
    vm.prank(liquidationModule);
    cashAsset.socializeLoss(requiredAmount / 2, accountId);
    preBalance = accounts.getBalance(accountId, cashAsset, 0);
    console.logInt(preBalance);
    console.log(" --- --- --- --- --- --- ");

    // All SM fees used to cover insolvency
    assertEq(cashAsset.accruedSmFees(), 0);
    assertEq(cashAsset.temporaryWithdrawFeeEnabled(), false);
  }

  function testSmFeeCanCoverSomeInsolvency() public {
    uint smFeeCut = 0.8 * 1e18;
    cashAsset.setSmFee(smFeeCut);

    uint newAccount = accounts.createAccount(address(this), manager);
    uint totalBorrow = cashAsset.totalBorrow();
    assertEq(totalBorrow, 0);

    // Increase total borrow amount
    uint requiredAmount = 1000 * 1e18;
    cashAsset.withdraw(newAccount, requiredAmount, address(this));

    vm.warp(block.timestamp + 1 weeks);
    cashAsset.accrueInterest();

    // Assert for sm fees
    assertGt(cashAsset.accruedSmFees(), 0);
    console.log("------------------------------");
    console.log("SM fees are", cashAsset.accruedSmFees());
    console.log("RequiredAmt", requiredAmount /2);
    console.log("------------------------------");

    // trigger insolvency
    vm.prank(liquidationModule);
    cashAsset.socializeLoss(requiredAmount / 2, accountId);

    // Some SM fees used to cover insolvency and insolvency still occurs
    assertEq(cashAsset.accruedSmFees(), 0);
    assertEq(cashAsset.temporaryWithdrawFeeEnabled(), true);
  }
}
