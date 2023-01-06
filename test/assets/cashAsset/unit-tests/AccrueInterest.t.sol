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
    cashAsset = new CashAsset(account, usdc);

    cashAsset.setWhitelistManager(address(manager), true);
    cashAsset.setInterestRateModel(rateModel);

    // 10000 USDC with 18 decimals
    depositedAmount = 10000 ether;
    usdc.mint(address(this), depositedAmount);
    usdc.approve(address(cashAsset), type(uint).max);

    accountId = account.createAccount(address(this), manager);

    cashAsset.deposit(accountId, depositedAmount);
    vm.warp(block.timestamp + 1 weeks);
  }

  function testSimpleAccrueInterest() public {
    uint amountToBorrow = 2000 ether;
    uint newAccount = account.createAccount(address(this), manager);
    uint totalBorrow = cashAsset.totalBorrow();
    assertEq(totalBorrow, 0);

    console.log("BalanceOf", usdc.balanceOf(address(cashAsset)));
    console.log("Equal s-b", cashAsset.totalSupply() - cashAsset.totalBorrow());

    uint usdcBefore = usdc.balanceOf(address(this));
    cashAsset.withdraw(newAccount, amountToBorrow, address(this));
    uint usdcAfter = usdc.balanceOf(address(this));

    totalBorrow = cashAsset.totalBorrow();
    console.log("TotalBorrow", totalBorrow / 1e18);

    uint util = rateModel.getUtilRate(cashAsset.totalSupply(), cashAsset.totalBorrow());
    console.log("Util is", util / 1e18);
    cashAsset.accrueInterest();

    console.log("wrap ahead one year");
    vm.warp(block.timestamp + 30 days);
    cashAsset.accrueInterest();
    // Check that the interest is what are expecting
    // Manually calculate the interest rate
    assertEq(usdcAfter - usdcBefore, amountToBorrow);
    assertEq(totalBorrow, amountToBorrow);

    uint balanceOf = usdc.balanceOf(address(cashAsset));
    uint totalBorrow1 = cashAsset.totalBorrow();
    uint totalSupply1 = cashAsset.totalSupply();
    console.log("BalanceOf", balanceOf);
    console.log("Shouldsam", totalSupply1 - totalBorrow1);
    console.log("TotalSupp", totalSupply1);
    console.log("TotalBorr", totalBorrow1);
  }
}
