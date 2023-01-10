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
    cashAsset = new CashAsset(account, usdc, rateModel);
    cashAsset.setWhitelistManager(address(manager), true);
    cashAsset.setInterestRateModel(rateModel);

    // 100000 USDC with 18 decimals
    depositedAmount = 100000e18;
    usdc.mint(address(this), depositedAmount);
    usdc.approve(address(cashAsset), type(uint).max);

    accountId = account.createAccount(address(this), manager);

    cashAsset.deposit(accountId, depositedAmount);
    console.log("Here 4");
    vm.warp(block.timestamp + 1 weeks);
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

    // After accrueInterest, should increase borrow and supply indexes
    cashAsset.accrueInterest();
    assertGt(cashAsset.borrowIndex(), 1e18);
    assertGt(cashAsset.supplyIndex(), 1e18);
  }

  function testAccrueInterestBalance() public {
    uint amountToBorrow = 2000e18;
    uint newAccount = account.createAccount(address(this), manager);
    uint totalBorrow = cashAsset.totalBorrow();
    assertEq(totalBorrow, 0);

    // Increase total borrow amount
    cashAsset.withdraw(newAccount, amountToBorrow, address(this));

    totalBorrow = cashAsset.totalBorrow();
    uint totalSupply = cashAsset.totalSupply();
    console.log("TotalBorrow", totalBorrow / 1e18);
    console.log("TotalSupply", totalSupply / 1e18);

    console.log("borrowIndex", cashAsset.borrowIndex());
    console.log("supplyIndex", cashAsset.supplyIndex());
    // Should increase borrow and supply indexes
    // cashAsset.accrueInterest();
    console.log("borrowIndex", cashAsset.borrowIndex());
    console.log("supplyIndex", cashAsset.supplyIndex());
    int bal = account.getBalance(newAccount, cashAsset, 0);
    console.log("acc bal", uint(-bal));
    assertEq(-int(amountToBorrow), bal);

    vm.warp(block.timestamp + 30 days);
    cashAsset.withdraw(newAccount, amountToBorrow, address(this));

    bal = account.getBalance(newAccount, cashAsset, 0);
    console.log("acc bal", uint(-bal));
    // Borrow amount should be > because bal now includes accrued interest
    assertGt(-int(amountToBorrow) * 2, bal);
  }
}
