// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {ISecurityModule} from "../../../src/interfaces/ISecurityModule.sol";
import {ISubAccounts} from "../../../src/interfaces/ISubAccounts.sol";
import {IManager} from "../../../src/interfaces/IManager.sol";
import {IAsset} from "../../../src/interfaces/IAsset.sol";

contract MockSM is ISecurityModule {
  ISubAccounts public immutable subAccounts;

  uint public accountId;

  int public smCashBalance;

  IAsset public immutable cash;

  constructor(ISubAccounts _account, IAsset _cash) {
    subAccounts = _account;
    cash = _cash;
  }

  function createAccountForSM(IManager _manager) external {
    accountId = subAccounts.createAccount(address(this), _manager);
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

    ISubAccounts.AssetTransfer memory transfer = ISubAccounts.AssetTransfer({
      fromAcc: accountId,
      toAcc: targetAccount,
      asset: cash,
      subId: 0,
      amount: int(cashAmountPaid),
      assetData: ""
    });

    subAccounts.submitTransfer(transfer, "");
  }

  function test() public {}
}
