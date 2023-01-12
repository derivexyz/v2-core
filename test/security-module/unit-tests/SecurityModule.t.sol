// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../shared/mocks/MockERC20.sol";
import "../../shared/mocks/MockManager.sol";

import "../../../src/assets/CashAsset.sol";
import "../../../src/Accounts.sol";

/**
 * @dev we use the real Accounts contract in these tests to simplify verification process
 */
contract UNIT_SecurityModule is Test {
  CashAsset cashAsset;
  MockERC20 usdc;
  MockManager manager;
  Accounts account;

  uint accountId;

  function setUp() public {
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    manager = new MockManager(address(account));

    usdc = new MockERC20("USDC", "USDC");

    cashAsset = new CashAsset(account, usdc);

    cashAsset.setWhitelistManager(address(manager), true);

    // 10000 USDC with 18 decimals
    usdc.mint(address(this), 10000 ether);
    usdc.approve(address(cashAsset), type(uint).max);

    accountId = account.createAccount(address(this), manager);
  }

  function testCanDepositIntoSecurityModule() public {
    
  }

  function testCanWithdrawFromSecurityModule() public {
    
  }

  function testCanAddWhitelistedModule() public {
    
  }
}