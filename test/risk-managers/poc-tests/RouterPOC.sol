// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IAccounts} from "src/interfaces/IAccounts.sol";
import {IAsset} from "src/interfaces/IAsset.sol";
import {IManager} from "src/interfaces/IManager.sol";

import "src/interfaces/IPCRM.sol";

contract OrderRouter {
  IAccounts immutable accounts;
  IAsset immutable cashAsset;
  IPCRM immutable pcrm;

  uint ownAcc;

  constructor(IAccounts _accounts, IPCRM _pcrm, IAsset _cashAsset) {
    accounts = _accounts;
    pcrm = _pcrm;
    cashAsset = _cashAsset;

    ownAcc = accounts.createAccount(address(this), IManager(address(_pcrm)));
  }

  function submitOrders(IAccounts.AssetTransfer[] memory transfers) external {
    // validate order signature, etc

    // transfer funds with accounts
    uint tradeId = accounts.submitTransfers(transfers, "");

    // get fee from pcrm (Base manager)
    uint accountA = transfers[0].fromAcc;
    uint fee = pcrm.feeCharged(tradeId, accountA);

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
