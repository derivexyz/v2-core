// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IAsset} from "src/interfaces/IAsset.sol";
import {ISubAccounts} from "src/interfaces/ISubAccounts.sol";

import "../../../shared/mocks/MockManager.sol";

// Dumb manager for test bench mark
// Dumb manager read all balances from account during handleAdjustment. (to estimate the SLOAD cost we need)
contract DumbManager is MockManager {
  constructor(address account_) MockManager(account_) {}

  /// @dev used to estimate gas cost by setting balances to 0
  function clearBalances(uint accountId, ISubAccounts.HeldAsset[] memory assetsToSettle) external {
    uint assetLen = assetsToSettle.length;
    for (uint i; i < assetLen; i++) {
      int balance = subAccounts.getBalance(accountId, assetsToSettle[i].asset, assetsToSettle[i].subId);
      subAccounts.managerAdjustment(
        ISubAccounts.AssetAdjustment({
          acc: accountId,
          asset: assetsToSettle[i].asset,
          subId: assetsToSettle[i].subId,
          amount: -balance, // set back to zero
          assetData: bytes32(0)
        })
      );
    }
  }

  function handleAdjustment(
    uint accountId,
    uint tradeId,
    address sender,
    ISubAccounts.AssetDelta[] memory deltas,
    bytes memory data
  ) public override {
    super.handleAdjustment(accountId, tradeId, sender, deltas, data);

    // read the value, so we calculate the SLOADs
    subAccounts.getAccountBalances(accountId);
  }

  // add in a function prefixed with test here to prevent coverage from picking it up.
  function testCoverageChill() public {}
}
