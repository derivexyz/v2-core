// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/math/SignedMath.sol";

import "lyra-utils/encoding/OptionEncoding.sol";
import "lyra-utils/arrays/UnorderedMemoryArray.sol";

import {ISubAccounts} from "../interfaces/ISubAccounts.sol";
import {ISRMPortfolioViewer} from "../interfaces/ISRMPortfolioViewer.sol";
import {ICashAsset} from "../interfaces/ICashAsset.sol";
import {IPerpAsset} from "../interfaces/IPerpAsset.sol";
import {IOptionAsset} from "../interfaces/IOptionAsset.sol";
import {IStandardManager} from "../interfaces/IStandardManager.sol";
import {BasePortfolioViewer} from "./BasePortfolioViewer.sol";

/**
 * @title SRMPortfolioViewer
 * @author Lyra
 * @notice Read only contract that helps with converting portfolio and balances
 */

contract SRMPortfolioViewer is BasePortfolioViewer, ISRMPortfolioViewer {
  using SafeCast for uint;
  using SafeCast for int;
  using UnorderedMemoryArray for uint[];

  ///@dev standard manager contract where we read the assetDetails from
  IStandardManager public standardManager;

  constructor(ISubAccounts _subAccounts, ICashAsset _cash) BasePortfolioViewer(_subAccounts, _cash) {}

  /**
   * @dev update the standard manager contract
   */
  function setStandardManager(IStandardManager srm) external onlyOwner {
    standardManager = srm;
  }

  /**
   * @dev get the portfolio struct for standard risk manager
   */
  function getSRMPortfolio(uint accountId) external view returns (IStandardManager.StandardManagerPortfolio memory) {
    ISubAccounts.AssetBalance[] memory assets = subAccounts.getAccountBalances(accountId);
    return arrangeSRMPortfolio(assets);
  }

  /**
   * @dev get the pre-trade portfolio of an standard account
   */
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
      uint marketId;
      for (uint8 id = 1; id < 255; id++) {
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
          portfolio.marketHoldings[i].option = IOptionAsset(address(currentAsset.asset));
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
   * @dev Count how many market the user has
   */
  function _countMarketsAndParseCash(ISubAccounts.AssetBalance[] memory userBalances)
    internal
    view
    returns (uint marketCount, int cashBalance, uint trackedMarketBitMap)
  {
    if (userBalances.length > standardManager.maxAccountSize()) revert SRM_TooManyAssets();

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
