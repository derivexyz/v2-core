// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IAsset} from "../interfaces/IAsset.sol";
import {ISubAccounts} from "../interfaces/ISubAccounts.sol";

/**
 * @title ArrayDeltaLib
 * @author Lyra
 * @notice util functions for AssetDeltaLib operations
 */
library AssetDeltaLib {
  /// @dev too many deltas
  error DL_DeltasTooLong();

  /**
   * @notice apply delta to the AssetDeltaArrayCache.deltas array.
   * @dev if this is an asset never seen before, add to the accountDelta.deltas array
   *      if this is an asset seen before, update the accountDelta.deltas entry
   * @dev will revert if the delta array is already full (100 entries);
   *
   */
  function addToAssetDeltaArray(ISubAccounts.AssetDeltaArrayCache memory cache, ISubAccounts.AssetDelta memory delta)
    internal
    pure
  {
    for (uint i; i < cache.deltas.length;) {
      if (cache.deltas[i].asset == delta.asset && cache.deltas[i].subId == delta.subId) {
        cache.deltas[i].delta += delta.delta;
        return;
      } else if (cache.deltas[i].asset == IAsset(address(0)) && cache.deltas[i].subId == 0) {
        // find the first empty element, write information
        cache.deltas[i] = delta;
        unchecked {
          cache.used += 1;
        }
        return;
      }

      unchecked {
        i++;
      }
    }
    revert DL_DeltasTooLong();
  }

  function getDeltasFromArrayCache(ISubAccounts.AssetDeltaArrayCache memory cache)
    internal
    pure
    returns (ISubAccounts.AssetDelta[] memory)
  {
    ISubAccounts.AssetDelta[] memory deltas = new ISubAccounts.AssetDelta[](cache.used);
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
    returns (ISubAccounts.AssetDelta[] memory)
  {
    ISubAccounts.AssetDelta[] memory deltas = new ISubAccounts.AssetDelta[](1);
    deltas[0] = ISubAccounts.AssetDelta({asset: asset, subId: uint96(subId), delta: delta});
    return deltas;
  }
}
