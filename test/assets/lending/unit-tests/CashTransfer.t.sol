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

  function testTransferToNewAccountDoesnotChangeBorrowOrSupply(uint amountToBorrow, uint trasnsferAmount) public {
    vm.assume(amountToBorrow <= depositedAmount);

    vm.assume(trasnsferAmount <= depositedAmount);

    // borrow some amount, make both totalSupply and totalBorrow none-negative
    uint borrowAccount = account.createAccount(address(this), manager);
    uint totalBorrow = lending.totalBorrow();
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

  function testTransferDoesnotChangeInvariant(uint amountToBorrow, int anyAmount) public {
    vm.assume(amountToBorrow <= depositedAmount);
    vm.assume(anyAmount <= int(depositedAmount));
    vm.assume(anyAmount > type(int96).min); // make sure it does not underflow

    // borrow some amount, make both totalSupply and totalBorrow none-negative
    uint borrowAccount = account.createAccount(address(this), manager);
    uint totalBorrow = lending.totalBorrow();
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

    // invariant: balanceOf = totalSupply - totalBalance holds
    assertEq(totalSupplyBefore - totalBorrowBefore, totalSupplyAfter - totalBorrowAfter);
  }
}
