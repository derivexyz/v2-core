// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "../../../shared/mocks/MockERC20.sol";
import "../../../shared/mocks/MockManager.sol";
import "../mocks/MockInterestRateModel.sol";

import "../../../../src/assets/CashAsset.sol";
import "../../../../src/SubAccounts.sol";

/**
 * @dev we deploy actual Account contract in these tests to simplify verification process
 */
contract UNIT_CashAssetDeposit is Test {
  CashAsset cashAsset;
  MockERC20 usdc;
  MockManager manager;
  MockManager badManager;
  SubAccounts subAccounts;
  IInterestRateModel rateModel;

  uint accountId;

  function setUp() public {
    subAccounts = new SubAccounts("Lyra Margin Accounts", "LyraMarginNFTs");

    manager = new MockManager(address(subAccounts));
    badManager = new MockManager(address(subAccounts));

    usdc = new MockERC20("USDC", "USDC");

    rateModel = new MockInterestRateModel(1e18);
    cashAsset = new CashAsset(subAccounts, usdc, rateModel, 0, address(0));

    cashAsset.setWhitelistManager(address(manager), true);

    // 10000 USDC with 18 decimals
    usdc.mint(address(this), 10000 ether);
    usdc.approve(address(cashAsset), type(uint).max);

    accountId = subAccounts.createAccount(address(this), manager);
  }

  function testRevertsForInvalidSubId() public {
    // TODO: wrong spot for test
    uint account2 = subAccounts.createAccount(address(this), manager);
    ISubAccounts.AssetTransfer memory transfer = ISubAccounts.AssetTransfer({
      fromAcc: accountId,
      toAcc: account2,
      asset: cashAsset,
      subId: 1,
      amount: 1e18,
      assetData: ""
    });
    vm.expectRevert(ICashAsset.CA_InvalidSubId.selector);
    subAccounts.submitTransfer(transfer, "");
  }

  function testCannotDepositIntoWeirdAccount() public {
    uint badAccount = subAccounts.createAccount(address(this), badManager);

    vm.expectRevert(IManagerWhitelist.MW_UnknownManager.selector);
    cashAsset.deposit(badAccount, 100 ether);
  }

  function testDepositAmountMatchForFirstDeposit() public {
    uint depositAmount = 100 ether;
    cashAsset.deposit(accountId, depositAmount);

    int balance = subAccounts.getBalance(accountId, cashAsset, 0);
    assertEq(balance, int(depositAmount));
  }

  function testDepositToANewAccount() public {
    uint depositAmount = 100 ether;
    uint newAccount = cashAsset.depositToNewAccount(address(this), depositAmount, manager);
    int balance = subAccounts.getBalance(newAccount, cashAsset, 0);
    assertEq(balance, int(depositAmount));
  }

  function testCannotDepositToANewAccountWithBadManager() public {
    uint depositAmount = 100 ether;
    vm.expectRevert(IManagerWhitelist.MW_UnknownManager.selector);
    cashAsset.depositToNewAccount(address(this), depositAmount, badManager);
  }
}

contract UNIT_LendingDeposit6Decimals is Test {
  CashAsset cashAsset;
  SubAccounts subAccounts;
  IInterestRateModel rateModel;

  uint accountId;

  function setUp() public {
    subAccounts = new SubAccounts("Lyra Margin Accounts", "LyraMarginNFTs");
    MockManager manager = new MockManager(address(subAccounts));
    MockERC20 usdc = new MockERC20("USDC", "USDC");

    // set USDC to 6 decimals
    usdc.setDecimals(6);

    rateModel = new MockInterestRateModel(1e18);
    cashAsset = new CashAsset(subAccounts, usdc, rateModel, 0, address(0));
    cashAsset.setWhitelistManager(address(manager), true);

    // 10000 USDC with 6 decimals
    usdc.mint(address(this), 10000e6);
    usdc.approve(address(cashAsset), type(uint).max);

    accountId = subAccounts.createAccount(address(this), manager);
  }

  function testDepositWorkWithTokensWith6Decimals() public {
    uint depositAmount = 100e6;
    cashAsset.deposit(accountId, depositAmount);

    int balance = subAccounts.getBalance(accountId, cashAsset, 0);

    // amount should be scaled to 18 decimals in account
    assertEq(balance, 100 ether);
  }
}

// test cases for asset > 18 decimals
contract UNIT_LendingDeposit20Decimals is Test {
  CashAsset cashAsset;
  SubAccounts subAccounts;
  IInterestRateModel rateModel;

  uint accountId;

  function setUp() public {
    subAccounts = new SubAccounts("Lyra Margin Accounts", "LyraMarginNFTs");
    MockManager manager = new MockManager(address(subAccounts));
    MockERC20 usdc = new MockERC20("USDC", "USDC");

    // set USDC to 20 decimals!
    usdc.setDecimals(20);

    rateModel = new MockInterestRateModel(1e18);
    cashAsset = new CashAsset(subAccounts, usdc, rateModel, 0, address(0));
    cashAsset.setWhitelistManager(address(manager), true);

    // 10000 USDC with 20 decimals
    usdc.mint(address(this), 10000e20);
    usdc.approve(address(cashAsset), type(uint).max);

    accountId = subAccounts.createAccount(address(this), manager);
  }

  function testDepositWorkWithTokensWith20Decimals() public {
    uint depositAmount = 100e20;
    cashAsset.deposit(accountId, depositAmount);

    int balance = subAccounts.getBalance(accountId, cashAsset, 0);

    // amount should be scaled to 18 decimals in account
    assertEq(balance, 100 ether);
  }
}
