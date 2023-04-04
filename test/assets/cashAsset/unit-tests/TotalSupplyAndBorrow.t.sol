// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../../shared/mocks/MockERC20.sol";
import "../../../shared/mocks/MockManager.sol";
import "../mocks/MockInterestRateModel.sol";
import "../../../../src/assets/CashAsset.sol";
import "../../../../src/Accounts.sol";

/**
 * @dev testing total supply and total borrow (& utilisation rate) before and after
 * asset transfers
 * deposit
 * withdraw
 */
contract UNIT_CashAssetTotalSupplyBorrow is Test {
  CashAsset cashAsset;
  MockERC20 usdc;
  MockManager manager;
  Accounts account;
  IInterestRateModel rateModel;

  uint accountId;

  uint depositedAmount = 10000 ether;

  function setUp() public {
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    manager = new MockManager(address(account));

    usdc = new MockERC20("USDC", "USDC");

    rateModel = new MockInterestRateModel(1e18);
    cashAsset = new CashAsset(account, usdc, rateModel, 0);

    cashAsset.setWhitelistManager(address(manager), true);

    // 10000 USDC with 18 decimals
    usdc.mint(address(this), depositedAmount);
    usdc.approve(address(cashAsset), type(uint).max);

    accountId = account.createAccount(address(this), manager);
    cashAsset.deposit(accountId, depositedAmount);
  }

  /* --------------------- *
   |      Transfers        *
   * --------------------- */

  function testNormalTransfersDoesnotChangeBorrowOrSupply() public {
    // if all balances before and after a tx are positive
    // both totalSupply and totalBorrow stays the same
    uint trasnsferAmount = depositedAmount / 2;

    uint totalSupplyBefore = cashAsset.totalSupply();
    uint totalBorrowBefore = cashAsset.totalBorrow();

    uint emptyAccount = account.createAccount(address(this), manager);

    // transfer cash to an empty account.
    AccountStructs.AssetTransfer memory transfer = AccountStructs.AssetTransfer({ // short option and give it to another person
      fromAcc: accountId,
      toAcc: emptyAccount,
      asset: IAsset(cashAsset),
      subId: 0,
      amount: int(trasnsferAmount),
      assetData: bytes32(0)
    });
    account.submitTransfer(transfer, "");

    uint totalBorrowAfter = cashAsset.totalBorrow();
    uint totalSupplyAfter = cashAsset.totalSupply();

    // total supply and total borrow is the same
    assertEq(totalSupplyBefore, totalSupplyAfter);
    assertEq(totalBorrowBefore, totalBorrowAfter);
  }

  function testBorrowWillChangeSupplyAndTotalBorrow() public {
    // if someone with 0 balance transfer to another account (borrow from the system)
    // making the balances: -1000 & 1000: this will be reflected by both totalBorrow and totalSupply

    uint trasnsferAmount = depositedAmount / 2;

    uint borrowAccount = account.createAccount(address(this), manager);

    uint totalSupplyBefore = cashAsset.totalSupply();
    uint totalBorrowBefore = cashAsset.totalBorrow();

    uint emptyAccount = account.createAccount(address(this), manager);

    // transfer cash to an empty account. (borrow account ended in negative balance)
    AccountStructs.AssetTransfer memory transfer = AccountStructs.AssetTransfer({ // short option and give it to another person
      fromAcc: borrowAccount,
      toAcc: emptyAccount,
      asset: IAsset(cashAsset),
      subId: 0,
      amount: int(trasnsferAmount),
      assetData: bytes32(0)
    });
    account.submitTransfer(transfer, "");

    uint totalBorrowAfter = cashAsset.totalBorrow();
    uint totalSupplyAfter = cashAsset.totalSupply();

    // total supply and total borrow is the same
    assertEq(totalSupplyBefore + trasnsferAmount, totalSupplyAfter);
    assertEq(totalBorrowBefore + trasnsferAmount, totalBorrowAfter);
  }

  function testFuzzNormalTransferToNewAccountDoesnotChangeBorrowOrSupply(uint amountToBorrow, uint trasnsferAmount)
    public
  {
    // if amount transfer is higher than deposited, user transfer their own funds without borrowing from the system
    vm.assume(amountToBorrow <= depositedAmount);

    vm.assume(trasnsferAmount <= depositedAmount);

    // borrow some amount, make both totalSupply and totalBorrow none-negative
    uint borrowAccount = account.createAccount(address(this), manager);
    cashAsset.withdraw(borrowAccount, amountToBorrow, address(this));

    uint totalSupplyBefore = cashAsset.totalSupply();
    uint totalBorrowBefore = cashAsset.totalBorrow();

    uint emptyAccount = account.createAccount(address(this), manager);

    // transfer cash to an empty account.
    AccountStructs.AssetTransfer memory transfer = AccountStructs.AssetTransfer({ // short option and give it to another person
      fromAcc: accountId,
      toAcc: emptyAccount,
      asset: IAsset(cashAsset),
      subId: 0,
      amount: int(trasnsferAmount),
      assetData: bytes32(0)
    });
    account.submitTransfer(transfer, "");

    uint totalBorrowAfter = cashAsset.totalBorrow();
    uint totalSupplyAfter = cashAsset.totalSupply();

    // total supply and total borrow is the same
    assertEq(totalSupplyBefore, totalSupplyAfter);
    assertEq(totalBorrowBefore, totalBorrowAfter);
  }

  function testFuzzTransferDoesnotChangeInvariant(uint amountToBorrow, int anyAmount) public {
    vm.assume(amountToBorrow <= depositedAmount);
    vm.assume(anyAmount <= int(depositedAmount));
    vm.assume(anyAmount > type(int96).min); // make sure it does not underflow

    // borrow some amount, make both totalSupply and totalBorrow none-negative
    uint borrowAccount = account.createAccount(address(this), manager);
    cashAsset.withdraw(borrowAccount, amountToBorrow, address(this));

    uint totalSupplyBefore = cashAsset.totalSupply();
    uint totalBorrowBefore = cashAsset.totalBorrow();

    // transfer cash to an empty account.
    AccountStructs.AssetTransfer memory transfer = AccountStructs.AssetTransfer({ // short option and give it to another person
      fromAcc: accountId,
      toAcc: borrowAccount,
      asset: IAsset(cashAsset),
      subId: 0,
      amount: anyAmount, // it can be moving positive and negative witin accounts
      assetData: bytes32(0)
    });
    account.submitTransfer(transfer, "");

    uint totalBorrowAfter = cashAsset.totalBorrow();
    uint totalSupplyAfter = cashAsset.totalSupply();

    // invariant: balanceOf = totalSupply - totalBorrow holds
    assertEq(totalSupplyBefore - totalBorrowBefore, totalSupplyAfter - totalBorrowAfter);
  }

  /* ------------------- *
   |      Deposits       *
   * ------------------- */

  function testFuzzDepositIncreasesTotalSupply(uint depositAmount) public {
    // deposit will increase supply if the account balance is > 0 after deposit.
    vm.assume(depositAmount <= 10000 ether);

    uint preSupply = cashAsset.totalSupply();

    usdc.mint(address(this), depositAmount);
    cashAsset.deposit(accountId, depositAmount);
    uint postSupply = cashAsset.totalSupply();
    assertEq(postSupply - preSupply, depositAmount);
  }

  function testFuzzDepositDecreasesTotalBorrow(uint amountToBorrow, uint depositAmount) public {
    // deposit will decrease total borrow if account starting balance is negative
    vm.assume(amountToBorrow <= 1000 ether);
    vm.assume(depositAmount <= amountToBorrow);

    uint newAccount = account.createAccount(address(this), manager);
    uint totalBorrow = cashAsset.totalBorrow();
    assertEq(totalBorrow, 0);

    uint usdcBefore = usdc.balanceOf(address(this));
    cashAsset.withdraw(newAccount, amountToBorrow, address(this));
    uint usdcAfter = usdc.balanceOf(address(this));

    assertEq(usdcAfter - usdcBefore, amountToBorrow);
    assertEq(cashAsset.totalBorrow(), amountToBorrow);

    cashAsset.deposit(newAccount, depositAmount);

    totalBorrow = cashAsset.totalBorrow();
    assertEq(totalBorrow, amountToBorrow - depositAmount);
  }

  function testFuzzDepositNegativeBalanceToPositiveBalance(uint depositAmount, uint withdrawAmount) public {
    // someone deposit to pay his own debt and ends in positive balance
    vm.assume(depositAmount <= 10000 ether);
    vm.assume(depositAmount >= withdrawAmount);

    // create some totalBorrow
    uint newAccount = account.createAccount(address(this), manager);

    uint usdcBefore = usdc.balanceOf(address(this));
    cashAsset.withdraw(newAccount, withdrawAmount, address(this));
    uint usdcAfter = usdc.balanceOf(address(this));

    assertEq(usdcAfter - usdcBefore, withdrawAmount);
    assertEq(cashAsset.totalBorrow(), withdrawAmount);

    // test state after deposit

    uint totalSupplyBefore = cashAsset.totalSupply();

    usdc.mint(address(this), depositAmount);
    cashAsset.deposit(newAccount, depositAmount);

    uint totalSupplyAfter = cashAsset.totalSupply();
    uint totalBorrowAfter = cashAsset.totalBorrow();

    int balance = account.getBalance(newAccount, cashAsset, 0);
    assertEq(balance, int(depositAmount) - int(withdrawAmount));

    // total supply is increased by amount above 0
    assertEq(totalSupplyAfter - totalSupplyBefore, depositAmount - withdrawAmount);

    // total borrow is repaid to 0
    assertEq(totalBorrowAfter, 0);
  }

  /* ------------------- *
   |      Withdraw       *
   * ------------------- */

  function testFuzzWithdrawDecreasesTotalSupply(uint withdrawAmount) public {
    // withdraw will decrease totalSupply if account started with positive balance
    vm.assume(withdrawAmount <= 10000 ether);

    uint beforeWithdraw = cashAsset.totalSupply();
    cashAsset.withdraw(accountId, withdrawAmount, address(this));
    uint afterWithdraw = cashAsset.totalSupply();
    assertEq(beforeWithdraw - withdrawAmount, afterWithdraw);
  }

  function testFuzzWithdrawIncreasesTotalBorrow(uint amountToBorrow) public {
    // withdraw will increase totalBorrow if account ended with a negative balance
    vm.assume(amountToBorrow <= 10000 ether);

    uint emptyAccount = account.createAccount(address(this), manager);
    uint totalBorrow = cashAsset.totalBorrow();
    assertEq(totalBorrow, 0);

    uint usdcBefore = usdc.balanceOf(address(this));
    cashAsset.withdraw(emptyAccount, amountToBorrow, address(this));
    uint usdcAfter = usdc.balanceOf(address(this));

    totalBorrow = cashAsset.totalBorrow();
    assertEq(usdcAfter - usdcBefore, amountToBorrow);
    assertEq(totalBorrow, amountToBorrow);
  }

  function testFuzzWithdrawPositiveBalanceToNegativeBalance(uint depositAmount, uint withdrawAmount) public {
    // if someone withraw more than they have in cash balance
    // the final negative amount should be added to total borrow
    vm.assume(withdrawAmount <= 10000 ether);
    vm.assume(depositAmount <= withdrawAmount);

    usdc.mint(address(this), depositedAmount);
    uint newAccount = account.createAccount(address(this), manager);
    cashAsset.deposit(newAccount, depositAmount);

    // test after withdraw

    cashAsset.withdraw(newAccount, withdrawAmount, address(this));
    uint totalBorrow = cashAsset.totalBorrow();

    int balance = account.getBalance(newAccount, cashAsset, 0);
    assertEq(balance, int(depositAmount) - int(withdrawAmount));
    assertEq(totalBorrow, withdrawAmount - depositAmount);
  }
}
