// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/math/SignedMath.sol";
import "lyra-utils/decimals/DecimalMath.sol";

import "openzeppelin/access/Ownable2Step.sol";

import "lyra-utils/encoding/OptionEncoding.sol";
import "lyra-utils/arrays/UnorderedMemoryArray.sol";

import {ISubAccounts} from "../interfaces/ISubAccounts.sol";
import {IPortfolioViewer} from "../interfaces/IPortfolioViewer.sol";
import {ICashAsset} from "../interfaces/ICashAsset.sol";
import {IPerpAsset} from "../interfaces/IPerpAsset.sol";
import {IOption} from "../interfaces/IOption.sol";
import {IStandardManager} from "../interfaces/IStandardManager.sol";
import {IPMRM} from "../interfaces/IPMRM.sol";
import {IPositionTracking} from "../interfaces/IPositionTracking.sol";
import {IManager} from "../interfaces/IPositionTracking.sol";

import {IGlobalSubIdOITracking} from "../interfaces/IGlobalSubIdOITracking.sol";

/**
 * @title PortfolioViewer
 * @author Lyra
 * @notice Read only contract that helps with converting portfolio and balances
 */

contract PortfolioViewer is Ownable, IPortfolioViewer {
  using DecimalMath for uint;
  using SafeCast for uint;
  using SafeCast for int;
  using UnorderedMemoryArray for uint[];

  IStandardManager public standardManager;
  IPMRM public pmrm;

  ISubAccounts public immutable subAccounts;
  ICashAsset public immutable cashAsset;

  /// @dev OI fee rate in BPS. Charged fee = contract traded * OIFee * future price
  mapping(address asset => uint) public OIFeeRateBPS;

  constructor(ISubAccounts _subAccounts, ICashAsset _cash) {
    subAccounts = _subAccounts;
    cashAsset = _cash;
  }

  function setStandardManager(IStandardManager srm) external onlyOwner {
    standardManager = srm;
  }

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

  //

  /**
   * @notice calculate the perpetual OI fee.
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

    // If the trade increased OI and we are past the cap, revert.
    if (preTradePos < postTradePos && postTradePos > totalPosCap) revert BM_AssetCapExceeded();
  }

  function getSRMPortfolio(uint accountId) external view returns (IStandardManager.StandardManagerPortfolio memory) {
    ISubAccounts.AssetBalance[] memory assets = subAccounts.getAccountBalances(accountId);
    return arrangeSRMPortfolio(assets);
  }

  function getSRMPortfolioPreTrade(uint accountId, ISubAccounts.AssetDelta[] calldata assetDeltas)
    external
    view
    returns (IStandardManager.StandardManagerPortfolio memory)
  {
    ISubAccounts.AssetBalance[] memory assets = undoAssetDeltas(accountId, assetDeltas);
    return arrangeSRMPortfolio(assets);
  }

  /**
   * @notice Arrange balances into standard manager portfolio struct
   * @param assets Array of balances for given asset and subId.
   */
  function arrangeSRMPortfolio(ISubAccounts.AssetBalance[] memory assets)
    public
    view
    returns (IStandardManager.StandardManagerPortfolio memory)
  {
    (uint marketCount, int cashBalance, uint marketBitMap) = _countMarketsAndParseCash(assets);

    IStandardManager.StandardManagerPortfolio memory portfolio = IStandardManager.StandardManagerPortfolio({
      cash: cashBalance,
      marketHoldings: new IStandardManager.MarketHolding[](marketCount)
    });

    // for each market, need to count how many expires there are
    // and initiate a ExpiryHolding[] array in the corresponding marketHolding
    for (uint i; i < marketCount; i++) {
      // 1. find the first market id
      uint8 marketId;
      for (uint8 id = 1; id < 256; id++) {
        uint masked = (1 << id);
        if (marketBitMap & masked == 0) continue;
        // mark this market id as used => flip it back to 0 with xor
        marketBitMap ^= masked;
        marketId = id;
        break;
      }
      portfolio.marketHoldings[i].marketId = marketId;

      // 2. filter through all balances and only find perp or option for this market
      uint numExpires;
      uint[] memory seenExpires = new uint[](assets.length);
      uint[] memory expiryOptionCounts = new uint[](assets.length);

      for (uint j; j < assets.length; j++) {
        ISubAccounts.AssetBalance memory currentAsset = assets[j];
        if (currentAsset.asset == cashAsset) continue;

        IStandardManager.AssetDetail memory detail = standardManager.assetDetails(currentAsset.asset);
        if (detail.marketId != marketId) continue;

        if (detail.assetType == IStandardManager.AssetType.Perpetual) {
          // if it's perp asset, update the perp position directly
          portfolio.marketHoldings[i].perp = IPerpAsset(address(currentAsset.asset));
          portfolio.marketHoldings[i].perpPosition = currentAsset.balance;
          portfolio.marketHoldings[i].depegPenaltyPos += SignedMath.abs(currentAsset.balance).toInt256();
        } else if (detail.assetType == IStandardManager.AssetType.Option) {
          portfolio.marketHoldings[i].option = IOption(address(currentAsset.asset));
          (uint expiry,,) = OptionEncoding.fromSubId(uint96(currentAsset.subId));
          uint expiryIndex;
          (numExpires, expiryIndex) = seenExpires.addUniqueToArray(expiry, numExpires);
          // print all seen expiries
          expiryOptionCounts[expiryIndex]++;
        } else {
          // base asset, update holding.basePosition directly. This balance should always be positive
          portfolio.marketHoldings[i].basePosition = currentAsset.balance;
        }
      }

      // 3. initiate expiry holdings in a marketHolding
      portfolio.marketHoldings[i].expiryHoldings = new IStandardManager.ExpiryHolding[](numExpires);
      // 4. initiate the option array in each expiry holding
      for (uint j; j < numExpires; j++) {
        portfolio.marketHoldings[i].expiryHoldings[j].expiry = seenExpires[j];
        portfolio.marketHoldings[i].expiryHoldings[j].options = new IStandardManager.Option[](expiryOptionCounts[j]);
        // portfolio.marketHoldings[i].expiryHoldings[j].minConfidence = 1e18;
      }

      // 5. put options into expiry holdings
      for (uint j; j < assets.length; j++) {
        ISubAccounts.AssetBalance memory currentAsset = assets[j];
        if (currentAsset.asset == cashAsset) continue;

        IStandardManager.AssetDetail memory detail = standardManager.assetDetails(currentAsset.asset);
        if (detail.marketId != marketId) continue;

        if (detail.assetType == IStandardManager.AssetType.Option) {
          (uint expiry, uint strike, bool isCall) = OptionEncoding.fromSubId(uint96(currentAsset.subId));
          uint expiryIndex = seenExpires.findInArray(expiry, numExpires).toUint256();
          uint nextIndex = portfolio.marketHoldings[i].expiryHoldings[expiryIndex].numOptions;
          portfolio.marketHoldings[i].expiryHoldings[expiryIndex].options[nextIndex] =
            IStandardManager.Option({strike: strike, isCall: isCall, balance: currentAsset.balance});

          portfolio.marketHoldings[i].expiryHoldings[expiryIndex].numOptions++;
          if (isCall) {
            portfolio.marketHoldings[i].expiryHoldings[expiryIndex].netCalls += currentAsset.balance;
          }
          if (currentAsset.balance < 0) {
            // short option will be added to depegPenaltyPos
            portfolio.marketHoldings[i].depegPenaltyPos -= currentAsset.balance;
            portfolio.marketHoldings[i].expiryHoldings[expiryIndex].totalShortPositions -= currentAsset.balance;
          }
        }
      }
    }
    return portfolio;
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

  /**
   * @dev Count how many market the user has
   */
  function _countMarketsAndParseCash(ISubAccounts.AssetBalance[] memory userBalances)
    internal
    view
    returns (uint marketCount, int cashBalance, uint trackedMarketBitMap)
  {
    ISubAccounts.AssetBalance memory currentAsset;

    // count how many unique markets there are
    for (uint i; i < userBalances.length; ++i) {
      currentAsset = userBalances[i];
      if (address(currentAsset.asset) == address(cashAsset)) {
        cashBalance = currentAsset.balance;
        continue;
      }

      // else, it must be perp or option for one of the registered assets

      // if marketId 1 is tracked, trackedMarketBitMap    = 0000..00010
      // if marketId 2 is tracked, trackedMarketBitMap    = 0000..00100
      // if both markets are tracked, trackedMarketBitMap = 0000..00110
      IStandardManager.AssetDetail memory detail = standardManager.assetDetails(userBalances[i].asset);
      uint marketBit = 1 << detail.marketId;
      if (trackedMarketBitMap & marketBit == 0) {
        marketCount++;
        trackedMarketBitMap |= marketBit;
      }
    }
  }
}
