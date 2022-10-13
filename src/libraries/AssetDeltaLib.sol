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
    AccountStructs.AssetDeltaArrayCache memory accountDelta,
    AccountStructs.AssetDelta memory delta
  ) internal pure {
    for (uint i; i < accountDelta.deltas.length;) {
      if (accountDelta.deltas[i].asset == delta.asset && accountDelta.deltas[i].subId == delta.subId) {
        accountDelta.deltas[i].delta += delta.delta;
        break;
      } else if (accountDelta.deltas[i].asset == IAsset(address(0)) && accountDelta.deltas[i].subId == 0) {
        // find the first empty element, write information
        accountDelta.deltas[i] = delta;
        accountDelta.used += 1;
        break;
      }

      unchecked {
        i++;
      }
    }
  }

  function getDeltasFromArrayCache(AccountStructs.AssetDeltaArrayCache memory cache)
    internal
    pure
    returns (AccountStructs.AssetDelta[] memory)
  {
    AccountStructs.AssetDelta[] memory deltas = new AccountStructs.AssetDelta[](cache.used);
    for (uint i; i < deltas.length;) {
      deltas[i] = cache.deltas[i];

      unchecked {
        i++;
      }
    }
    return deltas;
  }

  function getDeltasFromAdjustment(AccountStructs.AssetAdjustment memory adjustment)
    internal
    pure
    returns (AccountStructs.AssetDelta[] memory)
  {
    AccountStructs.AssetDelta[] memory deltas = new AccountStructs.AssetDelta[](1);
    deltas[0] =
      AccountStructs.AssetDelta({asset: adjustment.asset, subId: uint96(adjustment.subId), delta: adjustment.amount});
    return deltas;
  }

  function getDeltasFromTransfer(AccountStructs.AssetTransfer memory transfer, bool negative)
    internal
    pure
    returns (AccountStructs.AssetDelta[] memory)
  {
    AccountStructs.AssetDelta[] memory deltas = new AccountStructs.AssetDelta[](1);
    deltas[0] = AccountStructs.AssetDelta({
      asset: transfer.asset,
      subId: uint96(transfer.subId),
      delta: negative ? -transfer.amount : transfer.amount
    });
    return deltas;
  }
}
