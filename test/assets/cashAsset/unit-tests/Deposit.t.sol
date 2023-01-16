// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../../shared/mocks/MockERC20.sol";
import "../../../shared/mocks/MockManager.sol";

import "../../../../src/assets/CashAsset.sol";
import "../../../../src/Accounts.sol";

/**
 * @dev we deploy actual Account contract in these tests to simplify verification process
 */
contract UNIT_CashAssetDeposit is Test {
  CashAsset cashAsset;
  MockERC20 usdc;
  MockManager manager;
  MockManager badManager;
  Accounts account;
  InterestRateModel rateModel;

  uint accountId;

  function setUp() public {
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    manager = new MockManager(address(account));
    badManager = new MockManager(address(account));

    usdc = new MockERC20("USDC", "USDC");

    rateModel = new InterestRateModel(1e18, 1e18, 1e18, 1e18);
    cashAsset = new CashAsset(account, usdc, rateModel, 0, address(0));

    cashAsset.setWhitelistManager(address(manager), true);

    // 10000 USDC with 18 decimals
    usdc.mint(address(this), 10000 ether);
    usdc.approve(address(cashAsset), type(uint).max);

    accountId = account.createAccount(address(this), manager);
  }

  function testCannotDepositIntoWeirdAccount() public {
    uint badAccount = account.createAccount(address(this), badManager);

    vm.expectRevert(ICashAsset.CA_UnknownManager.selector);
    cashAsset.deposit(badAccount, 100 ether);
  }

  function testDepositAmountMatchForFirstDeposit() public {
    uint depositAmount = 100 ether;
    cashAsset.deposit(accountId, depositAmount);

    int balance = account.getBalance(accountId, cashAsset, 0);
    assertEq(balance, int(depositAmount));
  }
}

contract UNIT_LendingDeposit6Decimals is Test {
  CashAsset cashAsset;
  Accounts account;
  InterestRateModel rateModel;

  uint accountId;

  function setUp() public {
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");
    MockManager manager = new MockManager(address(account));
    MockERC20 usdc = new MockERC20("USDC", "USDC");

    // set USDC to 6 decimals
    usdc.setDecimals(6);

    rateModel = new InterestRateModel(1e18, 1e18, 1e18, 1e18);
    cashAsset = new CashAsset(account, usdc, rateModel, 0, address(0));
    cashAsset.setWhitelistManager(address(manager), true);

    // 10000 USDC with 6 decimals
    usdc.mint(address(this), 10000e6);
    usdc.approve(address(cashAsset), type(uint).max);

    accountId = account.createAccount(address(this), manager);
  }

  function testDepositWorkWithTokensWith6Decimals() public {
    uint depositAmount = 100e6;
    cashAsset.deposit(accountId, depositAmount);

    int balance = account.getBalance(accountId, cashAsset, 0);

    // amount should be scaled to 18 decimals in account
    assertEq(balance, 100 ether);
  }
}

// test cases for asset > 18 decimals
contract UNIT_LendingDeposit20Decimals is Test {
  CashAsset cashAsset;
  Accounts account;
  InterestRateModel rateModel;

  uint accountId;

  function setUp() public {
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");
    MockManager manager = new MockManager(address(account));
    MockERC20 usdc = new MockERC20("USDC", "USDC");

    // set USDC to 20 decimals!
    usdc.setDecimals(20);

    rateModel = new InterestRateModel(1e18, 1e18, 1e18, 1e18);
    cashAsset = new CashAsset(account, usdc, rateModel, 0, address(0));
    cashAsset.setWhitelistManager(address(manager), true);

    // 10000 USDC with 20 decimals
    usdc.mint(address(this), 10000e20);
    usdc.approve(address(cashAsset), type(uint).max);

    accountId = account.createAccount(address(this), manager);
  }

  function testDepositWorkWithTokensWith20Decimals() public {
    uint depositAmount = 100e20;
    cashAsset.deposit(accountId, depositAmount);

    int balance = account.getBalance(accountId, cashAsset, 0);

    // amount should be scaled to 18 decimals in account
    assertEq(balance, 100 ether);
  }
}
