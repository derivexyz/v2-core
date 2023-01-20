// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../shared/mocks/MockERC20.sol";
import "../../shared/mocks/MockManager.sol";

import "../../../src/SecurityModule.sol";
import "../../../src/assets/CashAsset.sol";
import "../../../src/Accounts.sol";

/**
 * @dev real Accounts contract
 * @dev real CashAsset contract
 * @dev real SecurityModule contract
 */
contract INTEGRATION_SecurityModule_CashAsset is Test {
  // OFAC is the bad guy
  address public constant badGuy = address(0x0fac);

  address public constant liquidation = address(0xdead);

  CashAsset cashAsset = CashAsset(address(0xca7777));
  MockERC20 usdc;
  MockManager manager;
  Accounts accounts;
  SecurityModule securityModule;

  uint smAccId;
  uint accountId;

  function setUp() public {
    accounts = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    manager = new MockManager(address(accounts));

    usdc = new MockERC20("USDC", "USDC");
    usdc.setDecimals(6);

    cashAsset = new CashAsset(accounts, usdc);

    cashAsset.setWhitelistManager(address(manager), true);

    securityModule = new SecurityModule(accounts, cashAsset, usdc, manager);

    smAccId = securityModule.accountId();

    // 10000 USDC with 6 decimals
    usdc.mint(address(this), 20_000_000e6);
    usdc.approve(address(securityModule), type(uint).max);

    accountId = accounts.createAccount(address(this), manager);
  }

  function testDepositIntoSM() public {
    uint depositAmount = 1000e6;

    securityModule.deposit(depositAmount);

    // first deposit get equivelant share of USDC <> seuciry module share
    uint shares = securityModule.balanceOf(address(this));
    assertEq(shares, depositAmount);

    // cash in account is also updated
    int cashBalance = accounts.getBalance(securityModule.accountId(), IAsset(address(cashAsset)), 0);
    assertEq(cashBalance, 1000e18);
  }

  function testWithdrawFromSM() public {
    uint depositAmount = 1000e6;
    securityModule.deposit(depositAmount);

    uint sharesToWithdraw = securityModule.balanceOf(address(this)) / 2;

    uint usdcBefore = usdc.balanceOf(address(this));
    securityModule.withdraw(sharesToWithdraw, address(this));
    uint sharesLeft = securityModule.balanceOf(address(this));
    assertEq(sharesLeft, sharesToWithdraw); // 50% shares remaining

    // uint usdcAfter = usdc.balanceOf(address(this));
    // assertEq(usdcAfter - usdcBefore, depositAmount / 2);
  }

  // test the numbers increased when we have fee cut on SM
  function testWithdawFromSMCanCollectFeeFromInterest() public {}

  // test the numbers when we have withdraw fee enabled on cash asset
  function testWithdawFromSMWhenFeeSwitchIsOn() public {}
}