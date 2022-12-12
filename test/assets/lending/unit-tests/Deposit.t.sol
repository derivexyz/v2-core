// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../../../shared/mocks/MockERC20.sol";
import "../../../shared/mocks/MockManager.sol";

import "../../../../src/assets/Lending.sol";
import "../../../../src/Account.sol";

/**
 * @dev we deploy actual Account contract in these tests to simplify verification process
 */
contract UNIT_LendingDeposit is Test {
  Lending lending;
  MockERC20 usdc;
  MockManager manager;
  MockManager badManager;
  Account account;

  uint accountId;

  function setUp() public {
    account = new Account("Lyra Margin Accounts", "LyraMarginNFTs");

    manager = new MockManager(address(account));
    badManager = new MockManager(address(account));

    usdc = new MockERC20("USDC", "USDC");

    lending = new Lending(address(account), address(usdc));

    lending.setWhitelistManager(address(manager), true);

    // 10000 USDC with 18 decimals
    usdc.mint(address(this), 10000 ether);
    usdc.approve(address(lending), type(uint).max);

    accountId = account.createAccount(address(this), manager);
  }

  function testCannotDepositIntoWeirdAccount() public {
    uint badAccount = account.createAccount(address(this), badManager);

    vm.expectRevert(Lending.LA_UnknownManager.selector);
    lending.deposit(badAccount, 100 ether);
  }

  function testDepositAmountMatchForFirstDeposit() public {
    uint depositAmount = 100 ether;
    lending.deposit(accountId, depositAmount);

    int balance = account.getBalance(accountId, lending, 0);
    assertEq(balance, int(depositAmount));
  }

  function testDepositIntoNonEmptyAccountAccrueInterest() public {
    uint depositAmount = 100 ether;
    lending.deposit(accountId, depositAmount);

    vm.warp(block.timestamp + 1 days);

    // deposit again
    lending.deposit(accountId, depositAmount);

    assertEq(lending.lastTimestamp(), block.timestamp);
    // todo: test accrueInterest
  }
}

contract UNIT_LendingDeposit6Decimals is Test {
  Lending lending;
  Account account;

  uint accountId;

  function setUp() public {
    account = new Account("Lyra Margin Accounts", "LyraMarginNFTs");
    MockManager manager = new MockManager(address(account));
    MockERC20 usdc = new MockERC20("USDC", "USDC");

    // set USDC to 6 decimals
    usdc.setDecimals(6);

    lending = new Lending(address(account), address(usdc));
    lending.setWhitelistManager(address(manager), true);

    // 10000 USDC with 6 decimals
    usdc.mint(address(this), 10000e6);
    usdc.approve(address(lending), type(uint).max);

    accountId = account.createAccount(address(this), manager);
  }

  function testDepositWorkWithTokensWith6Decimals() public {
    uint depositAmount = 100e6;
    lending.deposit(accountId, depositAmount);

    int balance = account.getBalance(accountId, lending, 0);

    // amount should be scaled to 18 decimals in account
    assertEq(balance, 100 ether);
  }
}
