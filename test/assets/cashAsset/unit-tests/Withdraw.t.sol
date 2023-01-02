// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../../../shared/mocks/MockERC20.sol";
import "../../../shared/mocks/MockManager.sol";

import "../../../../src/assets/CashAsset.sol";
import "../../../../src/Account.sol";

/**
 * @dev we deploy actual Account contract in these tests to simplify verification process
 */
contract UNIT_CashAssetWithdraw is Test {
  CashAsset cashAsset;
  MockERC20 usdc;
  MockManager manager;
  MockManager badManager;
  Account account;
  address badActor = address(0x0fac);

  uint accountId;
  uint depositedAmount;

  function setUp() public {
    account = new Account("Lyra Margin Accounts", "LyraMarginNFTs");

    manager = new MockManager(address(account));
    badManager = new MockManager(address(account));

    usdc = new MockERC20("USDC", "USDC");

    cashAsset = new CashAsset(address(account), usdc);

    cashAsset.setWhitelistManager(address(manager), true);

    // 10000 USDC with 18 decimals
    depositedAmount = 10000 ether;
    usdc.mint(address(this), depositedAmount);
    usdc.approve(address(cashAsset), type(uint).max);

    accountId = account.createAccount(address(this), manager);

    cashAsset.deposit(accountId, depositedAmount);
  }

  function testCanWithdrawByAccountAmount() public {
    uint withdrawAmount = 100 ether;
    uint usdcBefore = usdc.balanceOf(address(this));
    cashAsset.withdraw(accountId, withdrawAmount, address(this));
    uint usdcAfter = usdc.balanceOf(address(this));

    assertEq(usdcAfter - usdcBefore, withdrawAmount);

    // cash balance updated in account
    int accBalance = account.getBalance(accountId, cashAsset, 0);
    assertEq(accBalance, int(depositedAmount - withdrawAmount));
  }

  function testCannotWithdrawFromOthersAccount() public {
    vm.prank(badActor);
    vm.expectRevert(CashAsset.CA_OnlyAccountOwner.selector);
    cashAsset.withdraw(accountId, 100 ether, address(this));
  }

  function testCannotWithdrawFromAccountNotControlledByTrustedManager() public {
    uint badAccount = account.createAccount(address(this), badManager);
    vm.expectRevert(CashAsset.CA_UnknownManager.selector);
    cashAsset.withdraw(badAccount, 100 ether, address(this));
  }

  function testBorrowIfManagerAllows() public {
    // user with an empty account (no cash balance) can withdraw USDC
    // essentially borrow from the cashAsset contract
    uint emptyAccount = account.createAccount(address(this), manager);

    uint amountToBorrow = 1000 ether;

    uint usdcBefore = usdc.balanceOf(address(this));
    cashAsset.withdraw(emptyAccount, amountToBorrow, address(this));
    uint usdcAfter = usdc.balanceOf(address(this));

    assertEq(usdcAfter - usdcBefore, amountToBorrow);

    int accBalance = account.getBalance(emptyAccount, cashAsset, 0);

    // todo: number might change based on interest
    assertEq(accBalance, -(int(amountToBorrow)));
  }
}
