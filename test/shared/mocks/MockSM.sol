// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../../src/interfaces/ISecurityModule.sol";
import "../../../src/interfaces/IAccounts.sol";
import "../../../src/interfaces/IManager.sol";
import "../../../src/interfaces/IAsset.sol";

contract MockSM is ISecurityModule {
  IAccounts public immutable accounts;

  uint public accountId;

  int public smCashBalance;

  IAsset public immutable cash;

  constructor(IAccounts _account, IAsset _cash) {
    accounts = _account;
    cash = _cash;
  }

  function createAccountForSM(IManager _manager) external {
    accountId = accounts.createAccount(address(this), _manager);
  }

  function mockBalance(int bal) external {
    smCashBalance = bal;
  }

  ///@dev mock the call to payout. Use the real account layer transfer to more easily test cash balances
  function requestPayout(uint targetAccount, uint cashAmountNeeded) external returns (uint cashAmountPaid) {
    uint cashBalance = uint(smCashBalance);
    if (cashBalance < cashAmountNeeded) {
      cashAmountPaid = cashBalance;
    } else {
      cashAmountPaid = cashAmountNeeded;
    }

    AccountStructs.AssetTransfer memory transfer = AccountStructs.AssetTransfer({
      fromAcc: accountId,
      toAcc: targetAccount,
      asset: cash,
      subId: 0,
      amount: int(cashAmountPaid),
      assetData: ""
    });

    accounts.submitTransfer(transfer, "");
  }

  function test() public {}
}
