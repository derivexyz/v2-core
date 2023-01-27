// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../../shared/mocks/MockERC20.sol";
import "../../../shared/mocks/MockManager.sol";
import "../mocks/MockInterestRateModel.sol";

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
  Accounts account;
  IInterestRateModel rateModel;

  uint accountId;
  uint depositedAmount;
  uint smAccount;

  function setUp() public {
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    manager = new MockManager(address(account));

    usdc = new MockERC20("USDC", "USDC");
    smAccount = account.createAccount(address(this), manager);

    rateModel = new MockInterestRateModel(0.5 * 1e18);
    cashAsset = new CashAsset(account, usdc, rateModel, smAccount, address(0));
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
    assertEq(newModel.minRate(), 0.8 * 1e18);
  }

  function testDepositUpdatesInterestTimestamp() public {
    uint depositAmount = 100 ether;
    usdc.mint(address(this), depositAmount * 2);
    cashAsset.deposit(accountId, depositAmount);

    vm.warp(block.timestamp + 1 days);

    // deposit again
    cashAsset.deposit(accountId, depositAmount);

    assertEq(cashAsset.lastTimestamp(), block.timestamp);
  }

  function testNoAccrueInterest() public {
    // Total borrow 0 so accrueInterest doesn't do anything
    uint totalBorrow = cashAsset.totalBorrow();
    assertEq(totalBorrow, 0);

    // Indexes should start at 1
    assertEq(cashAsset.borrowIndex(), 1e18);
    assertEq(cashAsset.supplyIndex(), 1e18);

    // After accrueInterest, borrow and supply indexes should stay same
    vm.warp(block.timestamp + 1);
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

  function testSetInvalidSmFeeCut() public {
    uint badFee = 1.1 * 1e18;
    vm.expectRevert(abi.encodeWithSelector(ICashAsset.CA_SmFeeInvalid.selector, badFee));
    cashAsset.setSmFee(badFee); // 10% cut
  }

  function testSmFeeCutFromInterest() public {
    uint amountToBorrow = 2000e18;
    uint newAccount = account.createAccount(address(this), manager);

    uint totalBorrow = cashAsset.totalBorrow();
    assertEq(totalBorrow, 0);

    // Increase total borrow amount
    cashAsset.withdraw(newAccount, amountToBorrow, address(this));

    // Indexes should start at 1
    assertEq(cashAsset.borrowIndex(), 1e18);
    assertEq(cashAsset.supplyIndex(), 1e18);

    vm.warp(block.timestamp + 2 weeks);

    // After accrueInterest, should increase borrow and supply indexes
    cashAsset.accrueInterest();
    assertGt(cashAsset.borrowIndex(), 1e18);
    assertGt(cashAsset.supplyIndex(), 1e18);

    assertEq(cashAsset.accruedSmFees(), 0);
    cashAsset.setSmFee(1e17); // 10% cut

    vm.warp(block.timestamp + 200 weeks);
    cashAsset.accrueInterest();
    assertGt(cashAsset.accruedSmFees(), 0);

    assertEq(account.getBalance(smAccount, cashAsset, 0), 0);
    cashAsset.transferSmFees();
    assertGt(account.getBalance(smAccount, cashAsset, 0), 0);
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

    int account1Debt = -cashAsset.calculateBalanceWithInterest(account1);
    int account2Debt = -cashAsset.calculateBalanceWithInterest(account2);
    account1Debt -= int(amountToBorrow1);
    account2Debt -= int(amountToBorrow2);

    // Account2 should have more debt than account1 due to greater borrow
    assertGt(account2Debt, account1Debt);

    // AccountId should have grow in balance (supply only)
    assertGt(uint(cashAsset.calculateBalanceWithInterest(accountId)), depositedAmount);
  }

  function testPositiveSettledCashIncreasesCashBalance() public {
    uint amountToBorrow = 2000e18;
    uint account1 = account.createAccount(address(this), manager);

    uint cashExchangeRate = cashAsset.getCashToStableExchangeRate();
    cashAsset.withdraw(account1, amountToBorrow, address(this));
    assertEq(cashExchangeRate, 1e18);

    // Track printed cash
    int posSettledCash = 10000 * 1e18;
    vm.prank(address(manager));
    cashAsset.updateSettledCash(posSettledCash);

    // Increase cash balance reflected in increased exchange rate
    cashExchangeRate = cashAsset.getCashToStableExchangeRate();
    assertGt(cashExchangeRate, 1e18);
  }

  function testNegativeSettledCashDecreasesCashBalance() public {
    uint amountToBorrow = 2000e18;
    uint account1 = account.createAccount(address(this), manager);

    uint cashExchangeRate = cashAsset.getCashToStableExchangeRate();
    cashAsset.withdraw(account1, amountToBorrow, address(this));
    assertEq(cashExchangeRate, 1e18);

    // Track printed cash
    int negSettledCash = -10000 * 1e18;
    vm.prank(address(manager));
    cashAsset.updateSettledCash(negSettledCash);

    // Decrease cash balance reflected in decreased exchange rate
    cashExchangeRate = cashAsset.getCashToStableExchangeRate();

    // In a real example the burnt amount would also be reflected in the supply (hook adj)
    // which is cancelled out inside `getExchangeRate`
    assertLt(cashExchangeRate, 1e18);
  }

  // todo add to integration test with real rate model
  // function testPositiveSettledCashIncreaseInterest() public {
  //   uint amountToBorrow = 2000e18;
  //   uint newAccount = account.createAccount(address(this), manager);
  //   uint totalBorrow = cashAsset.totalBorrow();
  //   assertEq(totalBorrow, 0);

  //   // Increase total borrow amount
  //   cashAsset.withdraw(newAccount, amountToBorrow, address(this));

  //   // todo MOCK interest rate contract returns static value
  //   vm.prank(address(manager));
  //   int posSettledCash = 10000 * 1e18;
  //   cashAsset.updateSettledCash(posSettledCash);

  //   // Indexes should start at 1
  //   assertEq(cashAsset.borrowIndex(), 1e18);
  //   assertEq(cashAsset.supplyIndex(), 1e18);

  //   vm.warp(block.timestamp + 1);

  //   // After accrueInterest, should increase borrow and supply indexes
  //   cashAsset.accrueInterest();
  //   assertGt(cashAsset.borrowIndex(), 1e18);
  //   assertGt(cashAsset.supplyIndex(), 1e18);
  //   console.log("borrowIndex", cashAsset.borrowIndex());
  //   console.log("supplyIndex", cashAsset.supplyIndex());
  // }
  // todo add to integration test with real rate model
  function testNegativeSettledCashDecreaseInterest() public {
    uint amountToBorrow = 2000e18;
    uint newAccount = account.createAccount(address(this), manager);
    uint totalBorrow = cashAsset.totalBorrow();
    assertEq(totalBorrow, 0);

    // Increase total borrow amount
    cashAsset.withdraw(newAccount, amountToBorrow, address(this));

    // todo MOCK interest rate contract returns static value
    vm.prank(address(manager));
    int negSettledCash = -10000 * 1e18;
    cashAsset.updateSettledCash(negSettledCash);

    // Indexes should start at 1
    assertEq(cashAsset.borrowIndex(), 1e18);
    assertEq(cashAsset.supplyIndex(), 1e18);

    vm.warp(block.timestamp + 1);

    // After accrueInterest, should increase borrow and supply indexes
    cashAsset.accrueInterest();
    assertGt(cashAsset.borrowIndex(), 1e18);
    assertGt(cashAsset.supplyIndex(), 1e18);
    console.log("borrowIndex", cashAsset.borrowIndex());
    console.log("supplyIndex", cashAsset.supplyIndex());
  }
}
