// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./IMatcher.sol";
import "../../interfaces/ISubAccounts.sol";

// Handles transferring assets from one subaccount to another
// Verifies the owner of both subaccounts is the same.
// Only has to sign from one side (so has to call out to the
contract WithdrawalHandler is IMatcher {
  struct WithdrawalData {
    address asset;
    uint amount;
  }

  function matchOrders(VerifiedOrder[] memory orders, bytes memory) public {
    for (uint i = 0; i < orders.length; ++i) {
      WithdrawalData memory data = abi.decode(orders[i].data, (WithdrawalData));
    }
  }
}
