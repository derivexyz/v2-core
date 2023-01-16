// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../shared/mocks/MockERC20.sol";
import "../../shared/mocks/MockManager.sol";
import "../mocks/MockCash.sol";

import "../../../src/SecurityModule.sol";
import "../../../src/assets/CashAsset.sol";
import "../../../src/Accounts.sol";

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
  Accounts accounts;
  SecurityModule securityModule;

  uint smAccId;
  uint accountId;

  function setUp() public {
    accounts = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    manager = new MockManager(address(accounts));

    usdc = new MockERC20("USDC", "USDC");
    usdc.setDecimals(6);

    // // probably use mock
    mockCash = new MockCashAssetWithExchangeRate(accounts, usdc);
    mockCash.setTokenToCashRate(1e30); // 1e12 * 1e18

    securityModule = new SecurityModule(accounts, ICashAsset(address(mockCash)), usdc, manager);

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
  }

  function testWithdrawFromSM() public {
    uint depositAmount = 1000e6;
    securityModule.deposit(depositAmount);

    uint sharesToWithdraw = securityModule.balanceOf(address(this)) / 2;

    uint usdcBefore = usdc.balanceOf(address(this));
    uint expectedStable = depositAmount / 2;

    // mock the balanceWithInterset call to return the exact balance deposited
    mockCash.setAccBalanceWithInterest(smAccId, 1000e18);

    securityModule.withdraw(sharesToWithdraw, address(this));
    uint sharesLeft = securityModule.balanceOf(address(this));
    assertEq(sharesLeft, sharesToWithdraw); // 50% shares remaining

    uint usdcAfter = usdc.balanceOf(address(this));
    assertEq(usdcAfter - usdcBefore, expectedStable);
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
    securityModule.deposit(depositAmount);

    // create acc to get paid
    uint receiverAcc = accounts.createAccount(address(this), manager);
    securityModule.setWhitelistModule(liquidation, true);

    vm.startPrank(liquidation);
    securityModule.requestPayout(receiverAcc, 1000e18);
    vm.stopPrank();

    int cashLeftInSecurity = accounts.getBalance(smAccId, IAsset(address(mockCash)), 0);
    assertEq(cashLeftInSecurity, 999_000e18);

    int cashForReceiver = accounts.getBalance(receiverAcc, IAsset(address(mockCash)), 0);
    assertEq(cashForReceiver, 1000e18);
  }

  function testPayoutAmountIsCapped() public {
    // someone deposit 1000 first
    uint depositAmount = 1_000e6;
    securityModule.deposit(depositAmount);

    // create acc to get paid
    uint receiverAcc = accounts.createAccount(address(this), manager);
    securityModule.setWhitelistModule(liquidation, true);

    vm.startPrank(liquidation);
    uint amountCashPaid = securityModule.requestPayout(receiverAcc, 2000e18);
    vm.stopPrank();

    assertEq(amountCashPaid, 1000e18);
  }
}
