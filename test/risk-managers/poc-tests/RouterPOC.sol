// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/interfaces/IAccounts.sol";
import "src/interfaces/AccountStructs.sol";
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

  function submitOrders(AccountStructs.AssetTransfer[] memory transfers) external {
    // validate order signature, etc

    // transfer funds with accounts
    uint tradeId = accounts.submitTransfers(transfers, "");

    // get fee from pcrm (Base manager)
    uint accountA = transfers[0].fromAcc;
    uint fee = pcrm.feeCharged(tradeId, accountA);

    // refund fee to accountA
    AccountStructs.AssetTransfer[] memory refunds = new AccountStructs.AssetTransfer[](1);
    refunds[0] = AccountStructs.AssetTransfer({
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
