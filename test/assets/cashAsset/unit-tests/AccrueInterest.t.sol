// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../../shared/mocks/MockERC20.sol";
import "../../../shared/mocks/MockManager.sol";

import "../../../../src/assets/CashAsset.sol";
import "../../../../src/assets/InterestRateModel.sol";
import "../../../../src/Accounts.sol";

/**
 * @dev we deploy actual Account contract in these tests to simplify verification process
 */
contract UNIT_CashAssetAccrueInterest is Test {
  using ConvertDecimals for uint;

  CashAsset cashAsset;
  MockERC20 usdc;
  MockManager manager;
  MockManager badManager;
  Accounts account;
  InterestRateModel rateModel;

  uint accountId;
  uint depositedAmount;

  function setUp() public {
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    manager = new MockManager(address(account));
    badManager = new MockManager(address(account));

    usdc = new MockERC20("USDC", "USDC");

    uint minRate = 0.06 * 1e18;
    uint rateMultipler = 0.2 * 1e18;
    uint highRateMultipler = 0.4 * 1e18;
    uint optimalUtil = 0.6 * 1e18;
    rateModel = new InterestRateModel(minRate, rateMultipler, highRateMultipler, optimalUtil);
    cashAsset = new CashAsset(account, usdc, rateModel, address(0));
    cashAsset.setWhitelistManager(address(manager), true);
    cashAsset.setInterestRateModel(rateModel);

    // 100000 USDC with 18 decimals
    depositedAmount = 100000e18;
    usdc.mint(address(this), depositedAmount);
    usdc.approve(address(cashAsset), type(uint).max);

    accountId = account.createAccount(address(this), manager);

    cashAsset.deposit(accountId, depositedAmount);
    vm.warp(block.timestamp + 1 weeks);
  }

  function testSetNewInterestRateModel() public {
    uint minRate = 0.8 * 1e18;
    uint rateMultipler = 0.8 * 1e18;
    uint highRateMultipler = 0.8 * 1e18;
    uint optimalUtil = 0.8 * 1e18;

    // Make sure when setting new rateModel indexes are updated
    uint amountToBorrow = 2000e18;
    uint newAccount = account.createAccount(address(this), manager);
    uint totalBorrow = cashAsset.totalBorrow();
    assertEq(totalBorrow, 0);

    // Increase total borrow amount
    cashAsset.withdraw(newAccount, amountToBorrow, address(this));

    // Indexes should start at 1
    assertEq(cashAsset.borrowIndex(), 1e18);
    assertEq(cashAsset.supplyIndex(), 1e18);

    vm.warp(block.timestamp + 1);
    InterestRateModel newModel = new InterestRateModel(minRate, rateMultipler, highRateMultipler, optimalUtil);

    // Setting new rate model should update indexes
    cashAsset.setInterestRateModel(newModel);

    assertGt(cashAsset.borrowIndex(), 1e18);
    assertGt(cashAsset.supplyIndex(), 1e18);
    assertEq(cashAsset.rateModel().minRate(), 0.8 * 1e18);
  }

  function testNoAccrueInterest() public {
    // Total borrow 0 so accrueInterest doesn't do anything
    uint totalBorrow = cashAsset.totalBorrow();
    assertEq(totalBorrow, 0);

    // Indexes should start at 1
    assertEq(cashAsset.borrowIndex(), 1e18);
    assertEq(cashAsset.supplyIndex(), 1e18);

    // After accrueInterest, borrow and supply indexes should stay same
    cashAsset.accrueInterest();
    assertEq(cashAsset.borrowIndex(), 1e18);
    assertEq(cashAsset.supplyIndex(), 1e18);
  }

  function testSimpleAccrueInterest() public {
    uint amountToBorrow = 2000e18;
    uint newAccount = account.createAccount(address(this), manager);
    uint totalBorrow = cashAsset.totalBorrow();
    assertEq(totalBorrow, 0);

    // Increase total borrow amount
    cashAsset.withdraw(newAccount, amountToBorrow, address(this));

    // Indexes should start at 1
    assertEq(cashAsset.borrowIndex(), 1e18);
    assertEq(cashAsset.supplyIndex(), 1e18);

    vm.warp(block.timestamp + 1);

    // After accrueInterest, should increase borrow and supply indexes
    cashAsset.accrueInterest();
    assertGt(cashAsset.borrowIndex(), 1e18);
    assertGt(cashAsset.supplyIndex(), 1e18);
  }

  function testAccrueInterestDebtBalance() public {
    uint amountToBorrow = 2000e18;
    uint debtAccount = account.createAccount(address(this), manager);
    assertEq(cashAsset.totalBorrow(), 0);

    // Increase total borrow amount
    cashAsset.withdraw(debtAccount, amountToBorrow, address(this));

    // Should be equal because no interest accrued
    int bal = account.getBalance(debtAccount, cashAsset, 0);
    assertEq(bal, -int(amountToBorrow));

    // Fast forward time to accrue interest
    vm.warp(block.timestamp + 30 days);
    cashAsset.withdraw(debtAccount, amountToBorrow, address(this));

    // Borrow amount should be > because bal now includes accrued interest
    bal = account.getBalance(debtAccount, cashAsset, 0);
    assertGt(-int(amountToBorrow) * 2, bal);
  }

  function testAccrueInterestPositiveBalance() public {
    uint amountToBorrow = 2000e18;
    usdc.mint(address(this), amountToBorrow * 2);

    uint posAccount = account.createAccount(address(this), manager);
    uint debtAccount = account.createAccount(address(this), manager);

    // Create positive balance for new account
    cashAsset.deposit(posAccount, amountToBorrow);

    // Create debt for new account to accrue interest
    cashAsset.withdraw(debtAccount, amountToBorrow, address(this));

    int posBal = account.getBalance(posAccount, cashAsset, 0);
    assertEq(amountToBorrow, uint(posBal));

    vm.warp(block.timestamp + 30 days);
    cashAsset.deposit(posAccount, amountToBorrow);

    // Positive bal > because it has accrued interest
    posBal = account.getBalance(posAccount, cashAsset, 0);
    assertGt(posBal, int(amountToBorrow * 2));
  }

  function testAccrueInterestWithMultipleAccounts() public {
    uint amountToBorrow1 = 2000e18;
    uint amountToBorrow2 = 5000e18;
    uint account1 = account.createAccount(address(this), manager);
    uint account2 = account.createAccount(address(this), manager);
    assertEq(cashAsset.totalBorrow(), 0);

    cashAsset.withdraw(account1, amountToBorrow1, address(this));
    cashAsset.withdraw(account2, amountToBorrow2, address(this));

    // Indexes should start at 1
    assertEq(cashAsset.borrowIndex(), 1e18);
    assertEq(cashAsset.supplyIndex(), 1e18);

    vm.warp(block.timestamp + 1 weeks);

    cashAsset.accrueInterest();
    assertGt(cashAsset.borrowIndex(), 1e18);
    assertGt(cashAsset.supplyIndex(), 1e18);

    int account1Debt = -cashAsset.getBalance(account1);
    int account2Debt = -cashAsset.getBalance(account2);
    account1Debt -= int(amountToBorrow1);
    account2Debt -= int(amountToBorrow2);

    // Account2 should have more debt than account1 due to greater borrow
    assertGt(account2Debt, account1Debt);

    // AccountId should have grow in balance (supply only)
    assertGt(uint(cashAsset.getBalance(accountId)), depositedAmount);
  }
}
