// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import {ISubAccounts} from "../interfaces/ISubAccounts.sol";

import {IGlobalSubIdOITracking} from "../interfaces/IGlobalSubIdOITracking.sol";
import {IManager} from "../interfaces/IManager.sol";

/**
 * @title IBasePortfolioViewer
 * @author Lyra
 */
interface IBasePortfolioViewer {
  error BM_AssetCapExceeded();

  error BM_OIFeeRateTooHigh();

  function getAssetOIFee(IGlobalSubIdOITracking asset, uint subId, int delta, uint tradeId, uint price)
    external
    view
    returns (uint fee);

  function checkAllAssetCaps(IManager manager, uint accountId, uint tradeId) external view;

  function getPreviousAssetsLength(
    ISubAccounts.AssetBalance[] memory assetBalances,
    ISubAccounts.AssetDelta[] memory assetDeltas
  ) external view returns (uint);

  /// @dev Emitted when OI fee rate is set
  event OIFeeRateSet(address asset, uint oiFeeRate);
}
