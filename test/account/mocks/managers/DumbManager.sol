// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/interfaces/IAsset.sol";
import "src/interfaces/IAccount.sol";
import "src/interfaces/AccountStructs.sol";

import "../../../shared/mocks/MockManager.sol";

// Dumb manager for test bench mark
// Dumb manager read all balances from account during handleAdjustment. (to estimate the SLOAD cost we need)
contract DumbManager is MockManager {
  constructor(address account_) MockManager(account_) {}

  /// @dev used to estimate gas cost by setting balances to 0
  function clearBalances(uint accountId, AccountStructs.HeldAsset[] memory assetsToSettle) external {
    uint assetLen = assetsToSettle.length;
    for (uint i; i < assetLen; i++) {
      int balance = account.getBalance(accountId, assetsToSettle[i].asset, assetsToSettle[i].subId);
      account.managerAdjustment(
        AccountStructs.AssetAdjustment({
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
    address sender,
    AccountStructs.AssetDelta[] memory deltas,
    bytes memory data
  ) public override {
    super.handleAdjustment(accountId, sender, deltas, data);

    // read the value, so we calculate the SLOADs
    IAccount(account).getAccountBalances(accountId);
  }

  // add in a function prefixed with test here to prevent coverage to pick it up.
  function testCoverageChill() public {}
}
