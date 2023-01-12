// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../../../shared/mocks/MockERC20.sol";
import "../../../shared/mocks/MockManager.sol";

import "../../../../src/assets/CashAsset.sol";
import "../../../../src/Accounts.sol";

/**
 * @dev we deploy actual Account contract in these tests to simplify verification process
 */
contract UNIT_CashAssetWithdraw is Test {
  CashAsset cashAsset;
  MockERC20 usdc;
  MockManager manager;
  MockManager badManager;
  Accounts account;
  InterestRateModel rateModel;
  address badActor = address(0x0fac);

  uint accountId;
  uint depositedAmount;

  function setUp() public {
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    manager = new MockManager(address(account));
    badManager = new MockManager(address(account));

    usdc = new MockERC20("USDC", "USDC");

    rateModel = new InterestRateModel(1e18, 1e18, 1e18, 1e18);
    cashAsset = new CashAsset(account, usdc, rateModel);

    cashAsset.setWhitelistManager(address(manager), true);

    // 10000 USDC with 18 decimals
    depositedAmount = 10000 ether;
    usdc.mint(address(this), depositedAmount);
    usdc.approve(address(cashAsset), type(uint).max);

    accountId = account.createAccount(address(this), manager);

    cashAsset.deposit(accountId, depositedAmount);
  }

  function testCanWithdrawByAccountAmount() public {
    uint withdrawAmount = 100 ether;
    uint usdcBefore = usdc.balanceOf(address(this));
    cashAsset.withdraw(accountId, withdrawAmount, address(this));
    uint usdcAfter = usdc.balanceOf(address(this));

    assertEq(usdcAfter - usdcBefore, withdrawAmount);

    // cash balance updated in account
    int accBalance = account.getBalance(accountId, cashAsset, 0);
    assertEq(accBalance, int(depositedAmount - withdrawAmount));
  }

  function testCannotWithdrawFromOthersAccount() public {
    vm.prank(badActor);
    vm.expectRevert(ICashAsset.CA_OnlyAccountOwner.selector);
    cashAsset.withdraw(accountId, 100 ether, address(this));
  }

  function testCannotWithdrawFromAccountNotControlledByTrustedManager() public {
    uint badAccount = account.createAccount(address(this), badManager);
    vm.expectRevert(ICashAsset.CA_UnknownManager.selector);
    cashAsset.withdraw(badAccount, 100 ether, address(this));
  }

  function testBorrowIfManagerAllows() public {
    // user with an empty account (no cash balance) can withdraw USDC
    // essentially borrow from the cashAsset contract
    uint emptyAccount = account.createAccount(address(this), manager);

    uint amountToBorrow = 1000 ether;

    uint usdcBefore = usdc.balanceOf(address(this));
    cashAsset.withdraw(emptyAccount, amountToBorrow, address(this));
    uint usdcAfter = usdc.balanceOf(address(this));

    assertEq(usdcAfter - usdcBefore, amountToBorrow);

    int accBalance = account.getBalance(emptyAccount, cashAsset, 0);

    // todo: number might change based on interest
    assertEq(accBalance, -(int(amountToBorrow)));
  }
}

/**
 * @dev tests with mocked stable ERC20 with 20 decimals
 */
contract UNIT_CashAssetWithdrawLargeDecimals is Test {
  CashAsset cashAsset;
  MockERC20 usdc;
  MockManager manager;
  Accounts accounts;
  InterestRateModel rateModel;

  uint accountId;

  function setUp() public {
    accounts = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    manager = new MockManager(address(accounts));

    usdc = new MockERC20("USDC", "USDC");

    // usdc as 20 decimals
    usdc.setDecimals(20);

    rateModel = new InterestRateModel(1e18, 1e18, 1e18, 1e18);
    cashAsset = new CashAsset(accounts, usdc, rateModel);

    cashAsset.setWhitelistManager(address(manager), true);

    // 10000 USDC with 20 decimals
    uint depositAmount = 10000 * 1e20;
    usdc.mint(address(this), depositAmount);
    usdc.approve(address(cashAsset), type(uint).max);

    accountId = accounts.createAccount(address(this), manager);

    cashAsset.deposit(accountId, depositAmount);
  }

  function testWithdrawDustWillUpdateAccountBalance() public {
    // amount (7 * 1e-20) should be round up to (1 * 1e-18) in our account
    uint amountToWithdraw = 7;

    int cashBalanceBefore = accounts.getBalance(accountId, cashAsset, 0);

    cashAsset.withdraw(accountId, amountToWithdraw, address(this));

    int cashBalanceAfter = accounts.getBalance(accountId, cashAsset, 0);

    // cash balance in account is deducted by 1 wei
    assertEq(cashBalanceBefore - cashBalanceAfter, 1);
  }
}
