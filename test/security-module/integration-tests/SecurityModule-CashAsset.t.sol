// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "../../shared/mocks/MockERC20.sol";
import "../../shared/mocks/MockManager.sol";
import "../../risk-managers/mocks/MockDutchAuction.sol";

import "../../../src/SecurityModule.sol";
import "../../../src/assets/CashAsset.sol";
import "../../../src/assets/InterestRateModel.sol";
import "../../../src/SubAccounts.sol";
import "../../../src/interfaces/IDutchAuction.sol";
/**
 * @dev real Accounts contract
 * @dev real CashAsset contract
 * @dev real SecurityModule contract
 */

contract INTEGRATION_SecurityModule_CashAsset is Test {
  // OFAC is the bad guy
  address public constant badGuy = address(0x0fac);

  CashAsset cashAsset = CashAsset(address(0xca7777));
  MockDutchAuction auction;
  MockERC20 usdc;
  MockManager manager;
  SubAccounts subAccounts;
  SecurityModule securityModule;
  InterestRateModel rateModel;

  uint smAccId;
  uint accountId;

  function setUp() public {
    subAccounts = new SubAccounts("Lyra Margin Accounts", "LyraMarginNFTs");

    manager = new MockManager(address(subAccounts));

    auction = new MockDutchAuction();

    usdc = new MockERC20("USDC", "USDC");
    usdc.setDecimals(6);

    uint minRate = 0.06 * 1e18;
    uint rateMultiplier = 0.2 * 1e18;
    uint highRateMultiplier = 0.4 * 1e18;
    uint optimalUtil = 0.6 * 1e18;
    rateModel = new InterestRateModel(minRate, rateMultiplier, highRateMultiplier, optimalUtil);

    // security
    cashAsset = new CashAsset(subAccounts, usdc, rateModel);

    cashAsset.setWhitelistManager(address(manager), true);

    securityModule = new SecurityModule(subAccounts, cashAsset, IManager(manager));

    smAccId = securityModule.accountId();

    // 10000 USDC with 6 decimals
    usdc.mint(address(this), 20_000_000e6);
    usdc.approve(address(securityModule), type(uint).max);
    usdc.approve(address(cashAsset), type(uint).max);

    accountId = subAccounts.createAccount(address(this), manager);

    cashAsset.setSmFeeRecipient(smAccId);
    cashAsset.setLiquidationModule(auction);
  }

  function testDepositIntoSM() public {
    uint depositAmount = 1000e6;

    securityModule.donate(depositAmount);

    // cash in account is also updated
    int cashBalance = subAccounts.getBalance(securityModule.accountId(), IAsset(address(cashAsset)), 0);
    assertEq(cashBalance, 1000e18);
  }

  function testRecoverERC20() public {
    usdc.mint(address(securityModule), 100e6);

    securityModule.recoverERC20(address(usdc), address(this), 100e6);

    assertEq(usdc.balanceOf(address(securityModule)), 0);
  }

  function testWithdrawFromSM() public {
    uint depositAmount = 1000e6;
    securityModule.donate(depositAmount);

    securityModule.withdraw(depositAmount / 2, address(this));
    usdc.balanceOf(address(this));
  }

  function testPaySMFeeForInsolvency() public {
    // deposit cash to CashAsset directly
    uint tradingAcc = subAccounts.createAccount(address(this), manager);
    cashAsset.deposit(tradingAcc, 1000e6);

    // assume that sm has some fees (in cash)
    securityModule.donate(1000e6);

    // simulate insolvency: cash has less USDC than expected
    usdc.burn(address(cashAsset), 200e6);
    uint exchangeRate = cashAsset.getCashToStableExchangeRate();
    assertEq(exchangeRate, 0.9e18);

    // any one can trigger SM to bail out cash asset
    vm.prank(address(0x0fac));
    securityModule.payCashInsolvency();

    int smCashBalance = subAccounts.getBalance(smAccId, IAsset(address(cashAsset)), 0);
    assertEq(smCashBalance, 800e18);
  }
}
