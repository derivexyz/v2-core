// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/interfaces/IAsset.sol";

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
    AccountStructs.AssetDeltaArrayCache memory cache,
    AccountStructs.AssetDelta memory delta
  ) internal pure {
    unchecked {
      // both i++ and used cannot overflow
      for (uint i; i < cache.deltas.length; i++) {
        if (cache.deltas[i].asset == delta.asset && cache.deltas[i].subId == delta.subId) {
          cache.deltas[i].delta += delta.delta;
          break;
        } else if (cache.deltas[i].asset == IAsset(address(0)) && cache.deltas[i].subId == 0) {
          // find the first empty element, write information
          cache.deltas[i] = delta;
          cache.used += 1;
          break;
        }
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

  function getDeltasFromSingleAdjustment(IAsset asset, uint subId, int delta)
    internal
    pure
    returns (AccountStructs.AssetDelta[] memory)
  {
    AccountStructs.AssetDelta[] memory deltas = new AccountStructs.AssetDelta[](1);
    deltas[0] = AccountStructs.AssetDelta({asset: asset, subId: uint96(subId), delta: delta});
    return deltas;
  }
}
