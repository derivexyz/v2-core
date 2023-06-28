// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IStandardManager} from "./IStandardManager.sol";
import {ISubAccounts} from "../interfaces/ISubAccounts.sol";

import {IGlobalSubIdOITracking} from "../interfaces/IGlobalSubIdOITracking.sol";
import {IManager} from "../interfaces/IManager.sol";

/**
 * @title IPortfolioViewer
 * @author Lyra
 */
interface IPortfolioViewer {
  error BM_AssetCapExceeded();

  error BM_OIFeeRateTooHigh();

  function getAssetOIFee(IGlobalSubIdOITracking asset, uint subId, int delta, uint tradeId, uint price)
    external
    view
    returns (uint fee);

  function checkAllAssetCaps(IManager manager, uint accountId, uint tradeId) external view;

  function getSRMPortfolio(uint accountId) external view returns (IStandardManager.StandardManagerPortfolio memory);

  function getSRMPortfolioPreTrade(uint accountId, ISubAccounts.AssetDelta[] calldata assetDeltas)
    external
    view
    returns (IStandardManager.StandardManagerPortfolio memory);

  function arrangeSRMPortfolio(ISubAccounts.AssetBalance[] memory assets)
    external
    view
    returns (IStandardManager.StandardManagerPortfolio memory);

  function undoAssetDeltas(uint accountId, ISubAccounts.AssetDelta[] memory assetDeltas)
    external
    view
    returns (ISubAccounts.AssetBalance[] memory newAssetBalances);

  /// @dev Emitted when OI fee rate is set
  event OIFeeRateSet(address asset, uint oiFeeRate);
}
