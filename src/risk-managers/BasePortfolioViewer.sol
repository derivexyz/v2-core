// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/math/SignedMath.sol";
import "lyra-utils/decimals/DecimalMath.sol";

import "openzeppelin/access/Ownable2Step.sol";

import {ISubAccounts} from "../interfaces/ISubAccounts.sol";
import {IBasePortfolioViewer} from "../interfaces/IBasePortfolioViewer.sol";
import {ICashAsset} from "../interfaces/ICashAsset.sol";

import {IPositionTracking} from "../interfaces/IPositionTracking.sol";
import {IManager} from "../interfaces/IPositionTracking.sol";

import {IGlobalSubIdOITracking} from "../interfaces/IGlobalSubIdOITracking.sol";
import {ITraderCheck} from "../interfaces/ITraderCheck.sol";

/**
 * @title BasePortfolioViewer
 * @author Lyra
 * @notice Read only contract that helps with converting portfolio and balances
 */

contract BasePortfolioViewer is Ownable2Step, IBasePortfolioViewer {
  using DecimalMath for uint;
  using SafeCast for uint;
  using SafeCast for int;

  ISubAccounts public immutable subAccounts;
  ICashAsset public immutable cashAsset;

  ///////////////
  // Variables //
  ///////////////

  /// @dev OI fee rate in BPS. Charged fee = contract traded * OIFee * future price
  mapping(address asset => uint) public OIFeeRateBPS;

  /// @dev AllowList contract address
  ITraderCheck public allowList;

  constructor(ISubAccounts _subAccounts, ICashAsset _cash) {
    subAccounts = _subAccounts;
    cashAsset = _cash;
  }

  //////////////////////////
  //        Setter        //
  //////////////////////////

  /**
   * @notice Governance determined OI fee rate to be set
   * @dev Charged fee = contract traded * OIFee * spot
   * @param newFeeRate OI fee rate in BPS
   */
  function setOIFeeRateBPS(address asset, uint newFeeRate) external onlyOwner {
    if (newFeeRate > 0.2e18) {
      revert BM_OIFeeRateTooHigh();
    }

    OIFeeRateBPS[asset] = newFeeRate;

    emit OIFeeRateSet(asset, newFeeRate);
  }

  /**
   * @notice Governance determined allowList
   * @param _allowList The allowList contract, can be empty which will bypass allowList checks
   */
  function setAllowList(ITraderCheck _allowList) external onlyOwner {
    allowList = _allowList;
    emit AllowListSet(_allowList);
  }

  /////////////////////////
  //        View         //
  /////////////////////////

  /**
   * @dev revert if the accountID is not on the allow list
   */
  function verifyCanTrade(uint accountId) external view {
    if (!canTrade(accountId)) revert BM_CannotTrade();
  }

  /**
   * @dev return true if the owner of an account ID is on the allow list
   */
  function canTrade(uint accountId) public view returns (bool) {
    if (allowList == ITraderCheck(address(0))) {
      return true;
    }
    address user = subAccounts.ownerOf(accountId);
    return allowList.canTrade(user);
  }

  /**
   * @notice calculate the OI fee for an asset
   * @dev if the OI after a batched trade is increased, all participants will be charged a fee if he trades this asset
   */
  function getAssetOIFee(IGlobalSubIdOITracking asset, uint subId, int delta, uint tradeId, uint price)
    external
    view
    returns (uint fee)
  {
    bool oiIncreased = _getOIIncreased(asset, subId, tradeId);
    if (!oiIncreased) return 0;

    fee = SignedMath.abs(delta).multiplyDecimal(price).multiplyDecimal(OIFeeRateBPS[address(asset)]);
  }

  /**
   * @dev check if OI increased for a given asset and subId in a trade
   */
  function _getOIIncreased(IGlobalSubIdOITracking asset, uint subId, uint tradeId) internal view returns (bool) {
    (, uint oiBefore) = asset.openInterestBeforeTrade(subId, tradeId);
    uint oi = asset.openInterest(subId);
    return oi > oiBefore;
  }

  /**
   * @notice check that all assets in an account is below the cap
   * @dev this function assume all assets are compliant to IPositionTracking interface
   */
  function checkAllAssetCaps(IManager manager, uint accountId, uint tradeId) external view {
    address[] memory assets = subAccounts.getUniqueAssets(accountId);
    for (uint i; i < assets.length; i++) {
      if (assets[i] == address(cashAsset)) continue;

      _checkAssetCap(manager, IPositionTracking(assets[i]), tradeId);
    }
  }

  /**
   * @dev check that an asset is not over the total position cap for this manager
   */
  function _checkAssetCap(IManager manager, IPositionTracking asset, uint tradeId) internal view {
    uint totalPosCap = asset.totalPositionCap(manager);
    (, uint preTradePos) = asset.totalPositionBeforeTrade(manager, tradeId);
    uint postTradePos = asset.totalPosition(manager);

    // If the trade increased total position and we are past the cap, revert.
    if (preTradePos < postTradePos && postTradePos > totalPosCap) revert BM_AssetCapExceeded();
  }

  /**
   * @dev get the original balances state before a trade is executed
   */
  function undoAssetDeltas(uint accountId, ISubAccounts.AssetDelta[] memory assetDeltas)
    public
    view
    returns (ISubAccounts.AssetBalance[] memory newAssetBalances)
  {
    ISubAccounts.AssetBalance[] memory assetBalances = subAccounts.getAccountBalances(accountId);

    // keep track of how many new elements to add to the result. Can be negative (remove balances that end at 0)
    uint removedBalances = 0;
    uint newBalances = 0;
    ISubAccounts.AssetBalance[] memory preBalances = new ISubAccounts.AssetBalance[](assetDeltas.length);

    for (uint i = 0; i < assetDeltas.length; ++i) {
      ISubAccounts.AssetDelta memory delta = assetDeltas[i];
      if (delta.delta == 0) {
        continue;
      }
      bool found = false;
      for (uint j = 0; j < assetBalances.length; ++j) {
        ISubAccounts.AssetBalance memory balance = assetBalances[j];
        if (balance.asset == delta.asset && balance.subId == delta.subId) {
          found = true;
          assetBalances[j].balance = balance.balance - delta.delta;
          if (assetBalances[j].balance == 0) {
            removedBalances++;
          }
          break;
        }
      }
      if (!found) {
        preBalances[newBalances++] =
          ISubAccounts.AssetBalance({asset: delta.asset, subId: delta.subId, balance: -delta.delta});
      }
    }

    newAssetBalances = new ISubAccounts.AssetBalance[](assetBalances.length + newBalances - removedBalances);

    uint newBalancesIndex = 0;
    for (uint i = 0; i < assetBalances.length; ++i) {
      ISubAccounts.AssetBalance memory balance = assetBalances[i];
      if (balance.balance != 0) {
        newAssetBalances[newBalancesIndex++] = balance;
      }
    }
    for (uint i = 0; i < newBalances; ++i) {
      newAssetBalances[newBalancesIndex++] = preBalances[i];
    }

    return newAssetBalances;
  }
}
