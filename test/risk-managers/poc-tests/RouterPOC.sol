// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IAccounts} from "src/interfaces/IAccounts.sol";
import {IAsset} from "src/interfaces/IAsset.sol";

import "src/interfaces/IBaseManager.sol";
import "src/interfaces/IManager.sol";

contract OrderRouter {
  IAccounts immutable accounts;
  IAsset immutable cashAsset;
  IBaseManager immutable manager;

  uint ownAcc;

  constructor(IAccounts _accounts, IBaseManager _manager, IAsset _cashAsset) {
    accounts = _accounts;
    manager = _manager;
    cashAsset = _cashAsset;

    ownAcc = accounts.createAccount(address(this), IManager(address(manager)));
  }

  function submitOrders(IAccounts.AssetTransfer[] memory transfers) external {
    // validate order signature, etc

    // transfer funds with accounts
    uint tradeId = accounts.submitTransfers(transfers, "");

    // get fee from manager (Base manager)
    uint accountA = transfers[0].fromAcc;
    uint fee = manager.feeCharged(tradeId, accountA);

    // refund fee to accountA
    IAccounts.AssetTransfer[] memory refunds = new IAccounts.AssetTransfer[](1);
    refunds[0] = IAccounts.AssetTransfer({
      fromAcc: ownAcc,
      toAcc: accountA,
      asset: cashAsset,
      subId: 0,
      amount: int(fee),
      assetData: ""
    });
    accounts.submitTransfers(refunds, "");
  }

  // add this to be excluded from coverage report
  function test() public {}
}
