// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./IMatcher.sol";
import "../../interfaces/ISubAccounts.sol";

// Handles transferring assets from one subaccount to another
// Verifies the owner of both subaccounts is the same.
// Only has to sign from one side (so has to call out to the
contract TransferHandler is IMatcher {
  struct TransferData {
    uint toAccountId;
    Transfers[] transfers;
  }

  struct Transfers {
    address asset;
    uint subId;
    int amount;
  }

  function matchOrders(VerifiedOrder[] memory orders, bytes memory) public {
    for (uint i = 0; i < orders.length; ++i) {
      TransferData memory data = abi.decode(orders[i].data, (TransferData));

      // TODO: verify owner of both subaccounts is the same => also both have to be approved so we cant do this loop
      // something like: orders[0].owner == matching.ownerOf(data.toAccountId)

      ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](data.transfers.length);

      for (uint i = 0; i < data.transfers.length; ++i) {
        // We should probably check that we aren't creating more OI by doing this transfer?
        // Users might for some reason create long and short options in different accounts for free by using this method...

        transferBatch[i] = ISubAccounts.AssetTransfer({
          asset: IAsset(data.transfers[i].asset),
          fromAcc: orders[0].accountId,
          toAcc: data.toAccountId,
          subId: data.transfers[i].subId,
          amount: data.transfers[i].amount,
          assetData: bytes32(0)
        });
      }

      // accounts.submitTransfers(transferBatch, "");
    }
  }
}
