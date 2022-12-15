// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../../shared/mocks/MockERC20.sol";
import "../../../shared/mocks/MockManager.sol";
import "./PrinterManager.sol";

import "../../../../src/assets/Lending.sol";
import "../../../../src/Account.sol";

contract POC_AssetManagerWhitelist is Test {
  Lending lending;
  MockERC20 usdc;
  MockManager manager;
  MoneyPrinterManager badManager;
  Account account;

  uint accountId;

  address evil = address(0x0fac);

  function setUp() public {
    account = new Account("Lyra Margin Accounts", "LyraMarginNFTs");

    manager = new MockManager(address(account));
    badManager = new MoneyPrinterManager(address(account));

    usdc = new MockERC20("USDC", "USDC");

    lending = new Lending(address(account), address(usdc));

    // whitelist good manager
    lending.setWhitelistManager(address(manager), true);

    // 10000 USDC with 18 decimals
    usdc.mint(address(this), 10000 ether);
    usdc.approve(address(lending), type(uint).max);

    accountId = account.createAccount(address(this), manager);
  }

  function testBadAccountCanStealMoney() public {
    // somebody legit deposit USDC with good manager
    lending.deposit(accountId, 100 ether);

    // Bad people doing bad things
    address evil = address(0x0fac);

    vm.startPrank(evil);

    uint printAmount = 80 ether;

    uint badAccount = account.createAccount(evil, badManager);

    vm.expectRevert(Lending.LA_UnknownManager.selector);
    badManager.printMoney(address(lending), badAccount, int(printAmount));

    // lending.withdraw(badAccount, printAmount, evil);

    // assertEq(usdc.balanceOf(evil), printAmount);

    vm.stopPrank();
  }
}
