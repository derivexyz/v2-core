// SPDX-License-Identifier: UNLICENSED
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

  function testWithdrawFromSM() public {
    uint depositAmount = 1000e6;
    securityModule.donate(depositAmount);

    securityModule.withdraw(depositAmount / 2, address(this));
    usdc.balanceOf(address(this));
  }

  // test the numbers increased when we have fee cut on SM
  function testWithdrawFromSMCanCollectFeeFromInterest() public {}

  // test the numbers when we have withdraw fee enabled on cash asset
  function testWithdrawFromSMWhenFeeSwitchIsOn() public {}
}
