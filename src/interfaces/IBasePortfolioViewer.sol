// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {ITraderCheck} from "./ITraderCheck.sol";
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

  error BM_CannotTrade();

  /// @dev revert if this account is not on the allowlist
  function verifyCanTrade(uint accountId) external view;

  /// @dev return true if this account is on the allowlist
  function canTrade(uint accountId) external view returns (bool);

  function getAssetOIFee(IGlobalSubIdOITracking asset, uint subId, int delta, uint tradeId, uint price)
    external
    view
    returns (uint fee);

  function checkAllAssetCaps(IManager manager, uint accountId, uint tradeId) external view;

  function undoAssetDeltas(uint accountId, ISubAccounts.AssetDelta[] memory assetDeltas)
    external
    view
    returns (ISubAccounts.AssetBalance[] memory newAssetBalances);

  /// @dev Emitted when OI fee rate is set
  event OIFeeRateSet(address asset, uint oiFeeRate);

  event AllowListSet(ITraderCheck _allowList);
}
