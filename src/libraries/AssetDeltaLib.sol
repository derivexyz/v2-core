// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/interfaces/AccountStructs.sol";
import "forge-std/console2.sol";

/**
 * @title ArrayLib
 * @author Lyra
 * @notice util functions for AssetDeltaLib operations
 */
library AssetDeltaLib {
  /// @dev apply delta to the accountDelta structure.
  /// @dev if this is an asset never seen before, add to the accountDelta.deltas array
  ///      if this is an asset seen before, update the accountDelta.deltas entry
  function addToAssetDeltaArray(
    AccountStructs.AccountAssetDeltas memory accountDelta,
    AccountStructs.AssetDelta memory delta
  ) internal pure {
    for (uint i; i < accountDelta.deltas.length;) {
      if (accountDelta.deltas[i].asset == delta.asset && accountDelta.deltas[i].subId == delta.subId) {
        accountDelta.deltas[i].delta += delta.delta;
        break;
      } else if (accountDelta.deltas[i].asset == IAsset(address(0)) && accountDelta.deltas[i].subId == 0) {
        // find the first empty element, write information
        accountDelta.deltas[i] = delta;
        break;
      }

      unchecked {
        i++;
      }
    }
  }

  function getDeltasFromAdjustment(AccountStructs.AssetAdjustment memory adjustment, bool negative)
    internal
    pure
    returns (AccountStructs.AccountAssetDeltas memory)
  {
    AccountStructs.AccountAssetDeltas memory accountDeltas =
      AccountStructs.AccountAssetDeltas({deltas: new AccountStructs.AssetDelta[](1)});
    accountDeltas.deltas[0] = AccountStructs.AssetDelta({
      asset: adjustment.asset,
      subId: uint96(adjustment.subId),
      delta: negative ? -adjustment.amount : adjustment.amount
    });
    return accountDeltas;
  }

  function getDeltasFromTransfer(AccountStructs.AssetTransfer memory transfer, bool negative)
    internal
    pure
    returns (AccountStructs.AccountAssetDeltas memory)
  {
    AccountStructs.AccountAssetDeltas memory accountDeltas =
      AccountStructs.AccountAssetDeltas({deltas: new AccountStructs.AssetDelta[](1)});
    accountDeltas.deltas[0] = AccountStructs.AssetDelta({
      asset: transfer.asset,
      subId: uint96(transfer.subId),
      delta: negative ? -transfer.amount : transfer.amount
    });
    return accountDeltas;
  }
}
