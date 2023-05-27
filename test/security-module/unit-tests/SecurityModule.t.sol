// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "../../shared/mocks/MockERC20.sol";
import "../mocks/MockCash.sol";
import "../../shared/mocks/MockManager.sol";

import "../../../src/SecurityModule.sol";
import "../../../src/assets/CashAsset.sol";
import "../../../src/SubAccounts.sol";

/**
 * @dev we use the real Accounts contract in these tests to simplify verification process
 */
contract UNIT_SecurityModule is Test {
  // OFAC is the bad guy
  address public constant badGuy = address(0x0fac);

  address public constant liquidation = address(0xdead);

  MockCashAssetWithExchangeRate mockCash;
  MockERC20 usdc;
  MockManager manager;
  SubAccounts subAccounts;
  SecurityModule securityModule;

  uint smAccId;
  uint accountId;

  function setUp() public {
    subAccounts = new SubAccounts("Lyra Margin Accounts", "LyraMarginNFTs");

    manager = new MockManager(address(subAccounts));

    usdc = new MockERC20("USDC", "USDC");
    usdc.setDecimals(6);

    // // probably use mock
    mockCash = new MockCashAssetWithExchangeRate(subAccounts, usdc);
    mockCash.setTokenToCashRate(1e30); // 1e12 * 1e18

    securityModule = new SecurityModule(subAccounts, ICashAsset(address(mockCash)), IManager(manager));

    smAccId = securityModule.accountId();

    // 10000 USDC with 6 decimals
    usdc.mint(address(this), 20_000_000e6);
    usdc.approve(address(securityModule), type(uint).max);

    accountId = subAccounts.createAccount(address(this), manager);
  }

  function testDepositIntoSM() public {
    uint depositAmount = 1000e6;

    securityModule.donate(depositAmount);
    assertEq(uint(subAccounts.getBalance(smAccId, mockCash, 0)), 1000e18);
    assertEq(usdc.balanceOf(address(mockCash)), depositAmount);
  }

  function testWithdrawWithNoShare() public {
    // cover the line where total supply is 0
    uint shares = 1000e6;
    vm.expectRevert("ERC20: transfer amount exceeds balance");
    securityModule.withdraw(shares, address(this));
  }

  function testWithdrawFromSM() public {
    uint depositAmount = 1000e6;
    securityModule.donate(depositAmount);

    uint usdcBefore = usdc.balanceOf(address(this));

    securityModule.withdraw(depositAmount / 2, address(this));

    assertEq(usdc.balanceOf(address(mockCash)), depositAmount / 2);

    uint usdcAfter = usdc.balanceOf(address(this));
    assertEq(usdcAfter - usdcBefore, depositAmount / 2);
  }

  function testCannotAddWhitelistedModuleFromNonOwner() public {
    vm.prank(badGuy);

    vm.expectRevert();
    securityModule.setWhitelistModule(badGuy, true);
  }

  function testCanWhitelistModule() public {
    securityModule.setWhitelistModule(liquidation, true);
    assertEq(securityModule.isWhitelisted(liquidation), true);
  }

  function NonWhitelisteModuleCannotRequestPayout() public {
    vm.prank(badGuy);

    vm.expectRevert(ISecurityModule.SM_NotWhitelisted.selector);
    securityModule.requestPayout(accountId, 1000e18);
  }

  function testCanRequestPayoutFromWhitelistedModule() public {
    // someone deposit 1 million first
    uint depositAmount = 1000_000e6;
    securityModule.donate(depositAmount);

    // create acc to get paid
    uint receiverAcc = subAccounts.createAccount(address(this), manager);
    securityModule.setWhitelistModule(liquidation, true);

    vm.startPrank(liquidation);
    securityModule.requestPayout(receiverAcc, 1000e18);
    vm.stopPrank();

    int cashLeftInSecurity = subAccounts.getBalance(smAccId, IAsset(address(mockCash)), 0);
    assertEq(cashLeftInSecurity, 999_000e18);

    int cashForReceiver = subAccounts.getBalance(receiverAcc, IAsset(address(mockCash)), 0);
    assertEq(cashForReceiver, 1000e18);
  }

  function testPayoutAmountIsCapped() public {
    // someone deposit 1000 first
    uint depositAmount = 1_000e6;
    securityModule.donate(depositAmount);

    // create acc to get paid
    uint receiverAcc = subAccounts.createAccount(address(this), manager);
    securityModule.setWhitelistModule(liquidation, true);

    vm.startPrank(liquidation);
    uint amountCashPaid = securityModule.requestPayout(receiverAcc, 2000e18);
    vm.stopPrank();

    assertEq(amountCashPaid, 1000e18);
  }
}
