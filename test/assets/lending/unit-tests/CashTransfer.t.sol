// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../../shared/mocks/MockERC20.sol";
import "../../../shared/mocks/MockManager.sol";

import "../../../../src/assets/Lending.sol";
import "../../../../src/Account.sol";

/**
 * @dev testing state variable / invariants before and after asset transfers
 */
contract UNIT_CashAssetTransfer is Test {
  Lending lending;
  MockERC20 usdc;
  MockManager manager;
  Account account;

  uint accountId;

  uint depositedAmount = 10000 ether;

  function setUp() public {
    account = new Account("Lyra Margin Accounts", "LyraMarginNFTs");

    manager = new MockManager(address(account));

    usdc = new MockERC20("USDC", "USDC");

    lending = new Lending(address(account), address(usdc));

    lending.setWhitelistManager(address(manager), true);

    // 10000 USDC with 18 decimals
    usdc.mint(address(this), depositedAmount);
    usdc.approve(address(lending), type(uint).max);

    accountId = account.createAccount(address(this), manager);
    lending.deposit(accountId, depositedAmount);
  }

  function testNormalTransfersDoesnotChangeBorrowOrSupply() public {
    // if all balances before and after a transfer is positive, these numbers will not be updated
    uint trasnsferAmount = depositedAmount / 2;

    uint totalSupplyBefore = lending.totalSupply();
    uint totalBorrowBefore = lending.totalBorrow();

    uint emptyAccount = account.createAccount(address(this), manager);

    // transfer cash to an empty account.
    AccountStructs.AssetTransfer memory transfer = AccountStructs.AssetTransfer({ // short option and give it to another person
      fromAcc: accountId,
      toAcc: emptyAccount,
      asset: IAsset(lending),
      subId: 0,
      amount: int(trasnsferAmount),
      assetData: bytes32(0)
    });
    account.submitTransfer(transfer, "");

    uint totalBorrowAfter = lending.totalBorrow();
    uint totalSupplyAfter = lending.totalSupply();

    // total supply and total borrow is the same
    assertEq(totalSupplyBefore, totalSupplyAfter);
    assertEq(totalBorrowBefore, totalBorrowAfter);
  }

  function testTransferWhichCreateBorrowWillChangeSupplyAndBorrow() public {
    // if someone from balance 0 transfer to another account
    // making the balances: -1000 & 1000: this will be reflected by both totalBorrow and totalSupply
    // borrow some amount, make both totalSupply and totalBorrow none-negative

    uint trasnsferAmount = depositedAmount / 2;

    uint borrowAccount = account.createAccount(address(this), manager);

    uint totalSupplyBefore = lending.totalSupply();
    uint totalBorrowBefore = lending.totalBorrow();

    uint emptyAccount = account.createAccount(address(this), manager);

    // transfer cash to an empty account. (borrow account ended in negative balance)
    AccountStructs.AssetTransfer memory transfer = AccountStructs.AssetTransfer({ // short option and give it to another person
      fromAcc: borrowAccount,
      toAcc: emptyAccount,
      asset: IAsset(lending),
      subId: 0,
      amount: int(trasnsferAmount),
      assetData: bytes32(0)
    });
    account.submitTransfer(transfer, "");

    uint totalBorrowAfter = lending.totalBorrow();
    uint totalSupplyAfter = lending.totalSupply();

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
    lending.withdraw(borrowAccount, amountToBorrow, address(this));

    uint totalSupplyBefore = lending.totalSupply();
    uint totalBorrowBefore = lending.totalBorrow();

    uint emptyAccount = account.createAccount(address(this), manager);

    // transfer cash to an empty account.
    AccountStructs.AssetTransfer memory transfer = AccountStructs.AssetTransfer({ // short option and give it to another person
      fromAcc: accountId,
      toAcc: emptyAccount,
      asset: IAsset(lending),
      subId: 0,
      amount: int(trasnsferAmount),
      assetData: bytes32(0)
    });
    account.submitTransfer(transfer, "");

    uint totalBorrowAfter = lending.totalBorrow();
    uint totalSupplyAfter = lending.totalSupply();

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
    lending.withdraw(borrowAccount, amountToBorrow, address(this));

    uint totalSupplyBefore = lending.totalSupply();
    uint totalBorrowBefore = lending.totalBorrow();

    // transfer cash to an empty account.
    AccountStructs.AssetTransfer memory transfer = AccountStructs.AssetTransfer({ // short option and give it to another person
      fromAcc: accountId,
      toAcc: borrowAccount,
      asset: IAsset(lending),
      subId: 0,
      amount: anyAmount, // it can be moving positive and negative witin accounts
      assetData: bytes32(0)
    });
    account.submitTransfer(transfer, "");

    uint totalBorrowAfter = lending.totalBorrow();
    uint totalSupplyAfter = lending.totalSupply();

    // invariant: balanceOf = totalSupply - totalBorrow holds
    assertEq(totalSupplyBefore - totalBorrowBefore, totalSupplyAfter - totalBorrowAfter);
  }
}
