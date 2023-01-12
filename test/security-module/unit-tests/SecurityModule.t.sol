// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../shared/mocks/MockERC20.sol";
import "../../shared/mocks/MockManager.sol";

import "../../../src/SecurityModule.sol";
import "../../../src/assets/CashAsset.sol";
import "../../../src/Accounts.sol";

/**
 * @dev we use the real Accounts contract in these tests to simplify verification process
 */
contract UNIT_SecurityModule is Test {
  CashAsset cashAsset;
  MockERC20 usdc;
  MockManager manager;
  Accounts accounts;
  SecurityModule securityModule;

  uint accountId;

  function setUp() public {
    accounts = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    manager = new MockManager(address(accounts));

    usdc = new MockERC20("USDC", "USDC");
    usdc.setDecimals(6);

    // probably use mock
    cashAsset = new CashAsset(accounts, usdc);

    cashAsset.setWhitelistManager(address(manager), true);

    securityModule = new SecurityModule(accounts, cashAsset, usdc, manager);

    // 10000 USDC with 6 decimals
    usdc.mint(address(this), 10000e6);
    usdc.approve(address(securityModule), type(uint).max);

    accountId = accounts.createAccount(address(this), manager);
  }

  function testDepositIntoSecurityModule() public {
    uint depositAmount = 1000e6;
    securityModule.deposit(depositAmount);

    // first deposit get equivelant share of USDC <> seuciry module share
    uint shares = securityModule.balanceOf(address(this));
    assertEq(shares, depositAmount);

    int cashBalance = accounts.getBalance(securityModule.accountId(), IAsset(address(cashAsset)), 0);
    assertEq(cashBalance, 1000e18);
  }

  function testCanWithdrawFromSecurityModule() public {}

  function testCanAddWhitelistedModule() public {}
}
