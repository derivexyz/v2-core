// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/math/SignedMath.sol";

import "lyra-utils/decimals/DecimalMath.sol";
import "lyra-utils/decimals/SignedDecimalMath.sol";
import "lyra-utils/math/IntLib.sol";
import "lyra-utils/math/UintLib.sol";
import "lyra-utils/encoding/OptionEncoding.sol";
import "openzeppelin/access/Ownable2Step.sol";

import {IManager} from "src/interfaces/IManager.sol";
import {IAccounts} from "src/interfaces/IAccounts.sol";
import {IAsset} from "src/interfaces/IAsset.sol";
import {ICashAsset} from "src/interfaces/ICashAsset.sol";
import {IPerpAsset} from "src/interfaces/IPerpAsset.sol";
import {IOption} from "src/interfaces/IOption.sol";
import {IBasicManager} from "src/interfaces/IBasicManager.sol";
import {IForwardFeed} from "src/interfaces/IForwardFeed.sol";
import {IVolFeed} from "src/interfaces/IVolFeed.sol";
import {ILiquidatableManager} from "src/interfaces/ILiquidatableManager.sol";

import {ISettlementFeed} from "src/interfaces/ISettlementFeed.sol";
import {IDutchAuction} from "src/interfaces/IDutchAuction.sol";

import {ISpotFeed} from "src/interfaces/ISpotFeed.sol";

import {IOptionPricing} from "src/interfaces/IOptionPricing.sol";

import {BaseManager} from "./BaseManager.sol";

import "lyra-utils/arrays/UnorderedMemoryArray.sol";

import "forge-std/console2.sol";

/**
 * @title BasicManager
 * @author Lyra
 * @notice Risk Manager that margin perp and option in isolation.
 */

contract BasicManager is IBasicManager, ILiquidatableManager, BaseManager {
  using SignedDecimalMath for int;
  using DecimalMath for uint;
  using SafeCast for uint;
  using SafeCast for int;
  using IntLib for int;
  using UnorderedMemoryArray for uint[];

  ///////////////
  // Variables //
  ///////////////

  /// @dev Depeg IM parameters: use to increase margin requirement if USDC depeg
  DepegParams public depegParams;

  /// @dev Oracle that returns USDC / USD price
  ISpotFeed public stableFeed;

  /// @dev True if an IAsset address is whitelisted.
  mapping(IAsset asset => AssetDetail) public assetDetails;

  /// @dev Perp Margin Requirements: maintenance and initial margin requirements
  mapping(uint marketId => PerpMarginRequirements) public perpMarginRequirements;

  /// @dev Option Margin Parameters. See getIsolatedMargin for how it is used in the formula
  mapping(uint marketId => OptionMarginParameters) public optionMarginParams;

  /// @dev Oracle Contingency parameters. used to increase margin requirement if oracle has low confidence
  mapping(uint marketId => OracleContingencyParams) public oracleContingencyParams;

  /// @dev Mapping from marketId to spot price oracle
  mapping(uint marketId => ISpotFeed) public spotFeeds;

  /// @dev Mapping from marketId to market price of perps
  mapping(uint marketId => ISpotFeed) public perpFeeds;

  /// @dev Mapping from marketId to settlement price oracle
  mapping(uint marketId => ISettlementFeed) public settlementFeeds;

  /// @dev Mapping from marketId to forward price oracle
  mapping(uint marketId => IForwardFeed) public forwardFeeds;

  /// @dev Mapping from marketId to vol oracle
  mapping(uint marketId => IVolFeed) public volFeeds;

  /// @dev Mapping from marketId to forward price oracle
  mapping(uint marketId => IOptionPricing) public pricingModules;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(IAccounts accounts_, ICashAsset cashAsset_) BaseManager(accounts_, cashAsset_, IDutchAuction(address(0))) {}

  ////////////////////////
  //    Admin-Only     //
  ///////////////////////

  /**
   * @notice Whitelist an asset to be used in Manager
   * @dev the basic manager only support option asset & perp asset
   */
  function whitelistAsset(IAsset _asset, uint8 _marketId, AssetType _type) external onlyOwner {
    assetDetails[_asset] = AssetDetail({isWhitelisted: true, marketId: _marketId, assetType: _type});

    emit AssetWhitelisted(address(_asset), _marketId, _type);
  }

  /**
   * @notice Set the oracles for a market id
   */
  function setOraclesForMarket(
    uint8 marketId,
    ISpotFeed spotFeed,
    ISpotFeed perpFeed,
    IForwardFeed forwardFeed,
    ISettlementFeed settlementFeed,
    IVolFeed volFeed
  ) external onlyOwner {
    // registered asset
    spotFeeds[marketId] = spotFeed;
    perpFeeds[marketId] = perpFeed;
    forwardFeeds[marketId] = forwardFeed;
    settlementFeeds[marketId] = settlementFeed;
    volFeeds[marketId] = volFeed;

    emit OraclesSet(
      marketId, address(spotFeed), address(perpFeed), address(forwardFeed), address(settlementFeed), address(volFeed)
    );
  }

  /**
   * @notice Set perp maintenance margin requirement for an market
   * @param _mmRequirement new maintenance margin requirement
   * @param _imRequirement new initial margin requirement
   */
  function setPerpMarginRequirements(uint8 marketId, uint _mmRequirement, uint _imRequirement) external onlyOwner {
    if (_mmRequirement > _imRequirement || _mmRequirement == 0 || _mmRequirement >= 1e18 || _imRequirement >= 1e18) {
      revert BM_InvalidMarginRequirement();
    }

    perpMarginRequirements[marketId] = PerpMarginRequirements(_mmRequirement, _imRequirement);

    emit MarginRequirementsSet(marketId, _mmRequirement, _imRequirement);
  }

  /**
   * @notice Set the option margin parameters for an market
   */
  function setOptionMarginParameters(uint8 marketId, OptionMarginParameters calldata params) external onlyOwner {
    optionMarginParams[marketId] = params;

    emit OptionMarginParametersSet(
      marketId,
      params.scOffset1,
      params.scOffset2,
      params.mmSCSpot,
      params.mmSPSpot,
      params.mmSPMtm,
      params.unpairedScale
    );
  }

  /**
   * @notice Set the option margin parameters for an market
   */
  function setOracleContingencyParams(uint8 marketId, OracleContingencyParams calldata params) external onlyOwner {
    if (params.perpThreshold > 1e18 || params.optionThreshold > 1e18 || params.OCFactor > 1e18) {
      revert BM_InvalidOracleContingencyParams();
    }
    oracleContingencyParams[marketId] = params;

    emit OracleContingencySet(params.perpThreshold, params.optionThreshold, params.OCFactor);
  }

  /**
   * @notice Set the option margin parameters for an market
   *
   */
  function setDepegParameters(DepegParams calldata params) external onlyOwner {
    if (params.threshold > 1e18 || params.depegFactor > 3e18) revert BM_InvalidDepegParams();
    depegParams = params;

    emit DepegParametersSet(params.threshold, params.depegFactor);
  }

  /**
   * @notice Set feed for USDC / USD price
   *
   */
  function setStableFeed(ISpotFeed _stableFeed) external onlyOwner {
    stableFeed = _stableFeed;

    emit StableFeedUpdated(address(_stableFeed));
  }

  /**
   * @notice Set the pricing module
   * @param _pricing new pricing module
   */
  function setPricingModule(uint8 marketId, IOptionPricing _pricing) external onlyOwner {
    pricingModules[marketId] = IOptionPricing(_pricing);

    emit PricingModuleSet(marketId, address(_pricing));
  }

  ///////////////////////
  //   Account Hooks   //
  ///////////////////////

  /**
   * @notice Ensures asset is valid and Max Loss margin is met.
   * @param accountId Account for which to check trade.
   */
  function handleAdjustment(
    uint accountId,
    uint tradeId,
    address caller,
    IAccounts.AssetDelta[] calldata assetDeltas,
    bytes calldata managerData
  ) public override onlyAccounts {
    // check if account is valid
    _verifyCanTrade(accountId);

    // send data to oracles if needed
    _processManagerData(tradeId, managerData);

    // if account is only reduce perp position, increasing cash, or increasing option position, bypass check
    bool isRiskReducing = true;

    // check assets are only cash or whitelisted perp and options
    for (uint i = 0; i < assetDeltas.length; i++) {
      // allow cash
      if (address(assetDeltas[i].asset) == address(cashAsset)) {
        if (assetDeltas[i].delta < 0) isRiskReducing = false;
        continue;
      }

      AssetDetail memory detail = assetDetails[assetDeltas[i].asset];

      if (!detail.isWhitelisted) revert BM_UnsupportedAsset();

      if (detail.assetType == AssetType.Perpetual) {
        // settle perp PNL into cash if the user traded perp in this tx.
        _settlePerpRealizedPNL(IPerpAsset(address(assetDeltas[i].asset)), accountId);
        if (isRiskReducing) {
          // check if the delta and position has same sign
          // if so, we cannot bypass the risk check
          int perpPosition = accounts.getBalance(accountId, assetDeltas[i].asset, 0);
          if (perpPosition != 0 && assetDeltas[i].delta * perpPosition > 0) {
            isRiskReducing = false;
          }
        }
      } else {
        // if the user is only reducing option position, we don't need to check margin
        if (assetDeltas[i].delta < 0) {
          isRiskReducing = false;
        }
      }
    }

    // iterate through delta again and charge all fees
    _chargeAllOIFee(caller, accountId, tradeId, assetDeltas);

    // if all trades are only reducing risk, return early
    if (isRiskReducing) return;

    IAccounts.AssetBalance[] memory assetBalances = accounts.getAccountBalances(accountId);
    BasicManagerPortfolio memory portfolio = _arrangePortfolio(assetBalances);

    if (portfolio.cash < 0) revert BM_NoNegativeCash();

    // the net margin here should always be zero or negative, unless there is unrealized pnl from a perp that was not traded in this tx
    (int postIM,) = _getMarginAndMarkToMarket(accountId, portfolio, true);

    // cash deposited has to cover the margin requirement
    if (postIM < 0) {
      BasicManagerPortfolio memory prePortfolio = _arrangePortfolio(_undoAssetDeltas(accountId, assetDeltas));

      (int preIM,) = _getMarginAndMarkToMarket(accountId, prePortfolio, true);

      // allow the trade to pass if the net margin increased
      if (postIM > preIM) return;

      revert BM_PortfolioBelowMargin(accountId, -(postIM));
    }
  }

  /**
   * @notice get the net margin for the option positions. This is expected to be negative
   * @param accountId Account Id for which to check
   * @return netMargin net margin. If negative, the account is under margin requirement
   * @return totalMarkToMarket the mark-to-market value of the portfolio, should be positive unless portfolio is obviously insolvent
   */
  function _getMarginAndMarkToMarket(uint accountId, BasicManagerPortfolio memory portfolio, bool isInitial)
    internal
    view
    returns (int netMargin, int totalMarkToMarket)
  {
    int depegMultiplier = _getDepegMultiplier(isInitial);

    // for each markets, get margin and sum it up
    for (uint i = 0; i < portfolio.marketHoldings.length; i++) {
      (int margin, int markToMarket) =
        _getMarketMargin(accountId, portfolio.marketHoldings[i], isInitial, depegMultiplier);
      netMargin += margin;
      totalMarkToMarket += markToMarket;
    }

    totalMarkToMarket += portfolio.cash;
    netMargin += portfolio.cash;
  }

  /**
   * @dev if the stable feed for USDC / USD return price lower than threshold, add extra amount to im
   * @return a positive multiplier that should be multiply to S * sum(shorts + perps)
   */
  function _getDepegMultiplier(bool isInitial) internal view returns (int) {
    if (!isInitial) return 0;

    (uint usdcPrice,) = stableFeed.getSpot();
    if (usdcPrice.toInt256() >= depegParams.threshold) return 0;

    return (depegParams.threshold - int(usdcPrice)).multiplyDecimal(depegParams.depegFactor);
  }

  /**
   * @notice return the margin for a specific market, including perp & option position
   * @dev this function should normally return a negative number, -100e18 means it requires $100 cash as margin
   *      it's possible that it return positive number because of unrealizedPNL from the perp position
   */
  function _getMarketMargin(uint accountId, MarketHolding memory marketHolding, bool isInitial, int depegMultiplier)
    internal
    view
    returns (int margin, int markToMarket)
  {
    (int indexPrice, uint indexConf) = _getIndexPrice(marketHolding.marketId);

    // also getting confidence because we need to find the
    int netPerpMargin = _getNetPerpMargin(marketHolding, indexPrice, isInitial, indexConf);
    (int netOptionMargin, int optionMtm) = _getNetOptionMarginAndMtM(marketHolding, indexPrice, isInitial, indexConf);

    int depegMargin = 0;
    if (depegMultiplier != 0) {
      // depeg multiplier should be 0 for maintenance margin, or when there is no depeg
      int num = marketHolding.perpPosition.abs().toInt256() + marketHolding.totalShortPositions;
      depegMargin = -num.multiplyDecimal(depegMultiplier).multiplyDecimal(indexPrice);
    }

    int unrealizedPerpPNL;
    if (marketHolding.perpPosition != 0) {
      // if this function is called in handleAdjustment, unrealized perp pnl will always be 0 if this perp is traded
      // because it would have been settled.
      // If called as a view function or on perp assets didn't got traded in this tx, it will represent the value that
      // should be added as cash if it is settle now
      unrealizedPerpPNL = marketHolding.perp.getUnsettledAndUnrealizedCash(accountId);
    }

    // base value is the mark to market value of ETH or BTC hold in the account
    int baseValue;
    if (marketHolding.basePosition > 0) {
      int basePosition = marketHolding.basePosition;
      (uint usdcPrice,) = stableFeed.getSpot();
      // convert to denominate in USDC
      baseValue = basePosition.multiplyDecimal(indexPrice).divideDecimal(usdcPrice.toInt256());
    }

    margin = netPerpMargin + netOptionMargin + depegMargin + unrealizedPerpPNL;

    // unrealized pnl is the mark to market value of a perp position
    markToMarket = optionMtm + unrealizedPerpPNL + baseValue;
  }

  /**
   * @notice get the margin required for the perp position of an market
   * @param indexConf index confidence
   * @return netMargin for a perp position, always negative
   */
  function _getNetPerpMargin(MarketHolding memory marketHolding, int indexPrice, bool isInitial, uint indexConf)
    internal
    view
    returns (int netMargin)
  {
    int position = marketHolding.perpPosition;
    if (position == 0) return 0;

    // while calculating margin for perp, we use the perp market price oracle
    (uint perpPrice, uint confidence) = perpFeeds[marketHolding.marketId].getSpot();
    uint notional = position.abs().multiplyDecimal(perpPrice);
    uint requirement = isInitial
      ? perpMarginRequirements[marketHolding.marketId].imRequirement
      : perpMarginRequirements[marketHolding.marketId].mmRequirement;
    netMargin = -notional.multiplyDecimal(requirement).toInt256();

    if (!isInitial) return netMargin;

    // if the min of two confidences is below threshold, apply penalty (becomes more negative)
    uint minConf = UintLib.min(confidence, indexConf);
    OracleContingencyParams memory ocParam = oracleContingencyParams[marketHolding.marketId];
    if (ocParam.perpThreshold != 0 && minConf < ocParam.perpThreshold) {
      int diff = 1e18 - int(minConf);
      int penalty =
        diff.multiplyDecimal(ocParam.OCFactor).multiplyDecimal(indexPrice).multiplyDecimal(int(position.abs()));
      netMargin -= penalty;
    }
  }

  /**
   * @notice get the net margin for the option positions. This is expected to be negative
   * @param minConfidence minimum confidence of perp and index oracle. This will be used to compare with other oracles
   *        and if min of all confidence scores fall below a threshold, add a penalty to the margin
   */
  function _getNetOptionMarginAndMtM(
    MarketHolding memory marketHolding,
    int indexPrice,
    bool isInitial,
    uint minConfidence
  ) internal view returns (int netMargin, int totalMarkToMarket) {
    // for each expiry, sum up the margin requirement
    for (uint i = 0; i < marketHolding.expiryHoldings.length; i++) {
      (int forwardPrice, uint fwdConf) =
        _getForwardPrice(marketHolding.marketId, marketHolding.expiryHoldings[i].expiry);
      minConfidence = UintLib.min(minConfidence, fwdConf);

      {
        uint volConf =
          volFeeds[marketHolding.marketId].getExpiryMinConfidence(uint64(marketHolding.expiryHoldings[i].expiry));
        minConfidence = UintLib.min(minConfidence, volConf);
      }

      (int margin, int mtm) = _calcNetBasicMarginSingleExpiry(
        marketHolding.marketId,
        marketHolding.option,
        marketHolding.expiryHoldings[i],
        indexPrice,
        forwardPrice,
        isInitial
      );
      netMargin += margin;
      totalMarkToMarket += mtm;

      // add oracle contingency on each expiry, only for IM
      if (!isInitial) continue;
      OracleContingencyParams memory ocParam = oracleContingencyParams[marketHolding.marketId];
      if (ocParam.optionThreshold != 0 && minConfidence < uint(ocParam.optionThreshold)) {
        int diff = 1e18 - int(minConfidence);
        int penalty = diff.multiplyDecimal(ocParam.OCFactor).multiplyDecimal(indexPrice).multiplyDecimal(
          marketHolding.expiryHoldings[i].totalShortPositions
        );
        netMargin -= penalty;
      }
    }
  }

  /**
   * @notice Arrange portfolio into cash + arranged
   *         array of [strikes][calls / puts].
   *         Unlike PCRM, the forwards are purposefully not filtered.
   * @param assets Array of balances for given asset and subId.
   */
  function _arrangePortfolio(IAccounts.AssetBalance[] memory assets)
    internal
    view
    returns (BasicManagerPortfolio memory)
  {
    (uint marketCount, int cashBalance, uint marketBitMap) = _countMarketsAndParseCash(assets);

    BasicManagerPortfolio memory portfolio =
      BasicManagerPortfolio({cash: cashBalance, marketHoldings: new MarketHolding[](marketCount)});

    // for each market, need to count how many expires there are
    // and initiate a ExpiryHolding[] array in the corresponding
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
        IAccounts.AssetBalance memory currentAsset = assets[j];
        if (currentAsset.asset == cashAsset) continue;

        AssetDetail memory detail = assetDetails[currentAsset.asset];
        if (detail.marketId != marketId) continue;

        if (detail.assetType == AssetType.Perpetual) {
          // if it's perp asset, update the perp position directly
          portfolio.marketHoldings[i].perp = IPerpAsset(address(currentAsset.asset));
          portfolio.marketHoldings[i].perpPosition = currentAsset.balance;
        } else if (detail.assetType == AssetType.Option) {
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
      portfolio.marketHoldings[i].expiryHoldings = new ExpiryHolding[](numExpires);
      // 4. initiate the option array in each expiry holding
      for (uint j; j < numExpires; j++) {
        portfolio.marketHoldings[i].expiryHoldings[j].expiry = seenExpires[j];
        portfolio.marketHoldings[i].expiryHoldings[j].options = new Option[](expiryOptionCounts[j]);
        // portfolio.marketHoldings[i].expiryHoldings[j].minConfidence = 1e18;
      }

      // 5. put options into expiry holdings
      for (uint j; j < assets.length; j++) {
        IAccounts.AssetBalance memory currentAsset = assets[j];
        if (currentAsset.asset == cashAsset) continue;

        AssetDetail memory detail = assetDetails[currentAsset.asset];
        if (detail.marketId != marketId) continue;

        if (detail.assetType == AssetType.Option) {
          (uint expiry, uint strike, bool isCall) = OptionEncoding.fromSubId(uint96(currentAsset.subId));
          uint expiryIndex = seenExpires.findInArray(expiry, numExpires).toUint256();
          uint nextIndex = portfolio.marketHoldings[i].expiryHoldings[expiryIndex].numOptions;
          portfolio.marketHoldings[i].expiryHoldings[expiryIndex].options[nextIndex] =
            Option({strike: strike, isCall: isCall, balance: currentAsset.balance});

          portfolio.marketHoldings[i].expiryHoldings[expiryIndex].numOptions++;
          if (isCall) {
            portfolio.marketHoldings[i].expiryHoldings[expiryIndex].netCalls += currentAsset.balance;
          }
          if (currentAsset.balance < 0) {
            portfolio.marketHoldings[i].totalShortPositions -= currentAsset.balance;
            portfolio.marketHoldings[i].expiryHoldings[expiryIndex].totalShortPositions -= currentAsset.balance;
          }
        }
      }
    }

    return portfolio;
  }

  /**
   * @notice Calculate the required margin of the account.
   *      If the account's option require 10K cash, this function will return -10K
   *
   * @dev If an account's max loss is bounded, return min (max loss margin, isolated margin)
   *      If an account's max loss is unbounded, return isolated margin
   * @param expiryHolding strikes for single expiry
   */
  function _calcNetBasicMarginSingleExpiry(
    uint8 marketId,
    IOption option,
    ExpiryHolding memory expiryHolding,
    int indexPrice,
    int forwardPrice,
    bool isInitial
  ) internal view returns (int, int totalMarkToMarket) {
    // We make sure the evaluate the scenario at price = 0
    int maxLossMargin = _calcPayoffAtPrice(option, expiryHolding, 0);
    int totalIsolatedMargin = 0;

    for (uint i; i < expiryHolding.options.length; i++) {
      Option memory optionPos = expiryHolding.options[i];

      // calculate isolated margin for this strike, aggregate to isolatedMargin
      (int isolatedMargin, int markToMarket) =
        _getIsolatedMargin(marketId, expiryHolding.expiry, optionPos, indexPrice, forwardPrice, isInitial);
      totalIsolatedMargin += isolatedMargin;
      totalMarkToMarket += markToMarket;

      // calculate the max loss margin, update the maxLossMargin if it's lower than current
      maxLossMargin = SignedMath.min(_calcPayoffAtPrice(option, expiryHolding, optionPos.strike), maxLossMargin);
    }

    if (expiryHolding.netCalls < 0) {
      int unpairedScale = optionMarginParams[marketId].unpairedScale;
      maxLossMargin += expiryHolding.netCalls.multiplyDecimal(unpairedScale).multiplyDecimal(forwardPrice);
    }

    // return the better of the 2 is the margin
    return (SignedMath.max(totalIsolatedMargin, maxLossMargin), totalMarkToMarket);
  }

  /**
   * @notice Settle expired option positions in an account.
   * @dev This function can be called by anyone
   */
  function settleOptions(IOption option, uint accountId) external {
    if (!assetDetails[option].isWhitelisted) revert BM_UnsupportedAsset();
    _settleAccountOptions(option, accountId);
  }

  /**
   * @dev settle perp value with index price
   */
  function settlePerpsWithIndex(IPerpAsset perp, uint accountId) external {
    if (!assetDetails[perp].isWhitelisted) revert BM_UnsupportedAsset();
    _settlePerpUnrealizedPNL(perp, accountId);
  }

  ////////////////////////
  //   View Functions   //
  ////////////////////////

  /**
   * @dev return the total net margin of an account
   * @return margin if it is negative, the account is insolvent
   */
  function getMargin(uint accountId, bool isInitial) public view returns (int) {
    // get portfolio from array of balances
    IAccounts.AssetBalance[] memory assetBalances = accounts.getAccountBalances(accountId);
    BasicManagerPortfolio memory portfolio = _arrangePortfolio(assetBalances);
    (int margin,) = _getMarginAndMarkToMarket(accountId, portfolio, isInitial);
    return margin;
  }

  /**
   * @dev the function used by the auction contract
   */
  function getMarginAndMarkToMarket(uint accountId, bool isInitial, uint) external view returns (int, int) {
    IAccounts.AssetBalance[] memory assetBalances = accounts.getAccountBalances(accountId);
    BasicManagerPortfolio memory portfolio = _arrangePortfolio(assetBalances);
    return _getMarginAndMarkToMarket(accountId, portfolio, isInitial);
  }

  /**
   * @dev return the isolated margin for a single option position
   * @return margin negative number, indicate margin requirement for a position
   * @return markToMarket the estimated worth of this position
   */
  function getIsolatedMargin(uint8 marketId, uint strike, uint expiry, bool isCall, int balance, bool isInitial)
    external
    view
    returns (int margin, int markToMarket)
  {
    (int indexPrice,) = _getIndexPrice(marketId);
    (int forwardPrice,) = _getForwardPrice(marketId, expiry);
    Option memory optionPos = Option({strike: strike, isCall: isCall, balance: balance});
    return _getIsolatedMargin(marketId, expiry, optionPos, indexPrice, forwardPrice, isInitial);
  }

  //////////////////////////
  //       Internal       //
  //////////////////////////

  function _chargeAllOIFee(address caller, uint accountId, uint tradeId, IAccounts.AssetDelta[] calldata assetDeltas)
    internal
  {
    if (feeBypassedCaller[caller]) return;

    uint fee;
    // iterate through all asset changes, if it's option asset, change if OI increased
    for (uint i; i < assetDeltas.length; i++) {
      AssetDetail memory detail = assetDetails[assetDeltas[i].asset];
      if (detail.assetType == AssetType.Perpetual) {
        IPerpAsset perp = IPerpAsset(address(assetDeltas[i].asset));
        ISpotFeed perpFeed = perpFeeds[detail.marketId];
        fee += _getPerpOIFee(perp, perpFeed, assetDeltas[i].delta, tradeId);
      } else if (detail.assetType == AssetType.Option) {
        IOption option = IOption(address(assetDeltas[i].asset));
        IForwardFeed forwardFeed = forwardFeeds[detail.marketId];
        fee += _getOptionOIFee(option, forwardFeed, assetDeltas[i].delta, assetDeltas[i].subId, tradeId);
      }
    }

    if (fee > 0 && feeRecipientAcc != 0) {
      // transfer cash to fee recipient account. This might fail if feeRecipientAcc is not owned by manager
      _symmetricManagerAdjustment(accountId, feeRecipientAcc, cashAsset, 0, int(fee));
    }
  }

  /**
   * @dev Count how many market the user has
   */
  function _countMarketsAndParseCash(IAccounts.AssetBalance[] memory userBalances)
    internal
    view
    returns (uint marketCount, int cashBalance, uint trackedMarketBitMap)
  {
    IAccounts.AssetBalance memory currentAsset;

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
      AssetDetail memory detail = assetDetails[userBalances[i].asset];
      uint marketBit = 1 << detail.marketId;
      if (trackedMarketBitMap & marketBit == 0) {
        marketCount++;
        trackedMarketBitMap |= marketBit;
      }
    }
  }

  /**
   * @dev calculate isolated margin requirement for a given number of calls and puts
   */
  function _getIsolatedMargin(
    uint8 marketId,
    uint expiry,
    Option memory optionPos,
    int indexPrice,
    int forwardPrice,
    bool isInitial
  ) internal view returns (int margin, int markToMarket) {
    (uint vol,) = volFeeds[marketId].getVol(uint128(optionPos.strike), uint64(expiry));
    markToMarket =
      _getMarkToMarket(marketId, optionPos.balance, forwardPrice, optionPos.strike, expiry, vol, optionPos.isCall);

    // a long position doesn't have any "margin", cannot be used to offset other positions
    if (optionPos.balance > 0) return (margin, markToMarket);

    if (optionPos.isCall) {
      margin =
        _getIsolatedMarginForCall(marketId, markToMarket, optionPos.strike, optionPos.balance, indexPrice, isInitial);
    } else {
      margin =
        _getIsolatedMarginForPut(marketId, markToMarket, optionPos.strike, optionPos.balance, indexPrice, isInitial);
    }
  }

  /**
   * @dev calculate isolated margin requirement for a put option
   * @dev expected to return a negative number
   */
  function _getIsolatedMarginForPut(
    uint8 marketId,
    int markToMarket,
    uint strike,
    int amount,
    int indexPrice,
    bool isInitial
  ) internal view returns (int) {
    OptionMarginParameters memory params = optionMarginParams[marketId];

    int maintenanceMargin = SignedMath.max(
      params.mmSPSpot.multiplyDecimal(indexPrice).multiplyDecimal(amount), params.mmSPMtm.multiplyDecimal(markToMarket)
    ) + markToMarket;

    if (!isInitial) return maintenanceMargin;

    int otmRatio = (indexPrice - strike.toInt256()).divideDecimal(indexPrice);
    int imMultiplier = SignedMath.max(params.scOffset1 - otmRatio, params.scOffset2);

    // max or min?
    int margin =
      SignedMath.min(imMultiplier.multiplyDecimal(indexPrice).multiplyDecimal(amount) + markToMarket, maintenanceMargin);
    return margin;
  }

  /**
   * @dev calculate isolated margin requirement for a call option
   * @param amount expected a negative number, representing amount of shorts
   */
  function _getIsolatedMarginForCall(
    uint8 marketId,
    int markToMarket,
    uint strike,
    int amount,
    int indexPrice,
    bool isInitial
  ) internal view returns (int) {
    OptionMarginParameters memory params = optionMarginParams[marketId];

    if (!isInitial) {
      return (params.mmSCSpot.multiplyDecimal(indexPrice)).multiplyDecimal(amount) + markToMarket;
    }

    // this ratio become negative if option is ITM
    int otmRatio = (strike.toInt256() - indexPrice).divideDecimal(indexPrice);

    int imMultiplier = SignedMath.max(params.scOffset1 - otmRatio, params.scOffset2);

    int margin = (imMultiplier.multiplyDecimal(indexPrice)).multiplyDecimal(amount) + markToMarket;
    return margin;
  }

  /**
   * @notice Calculate the full portfolio payoff at a given settlement price.
   *         This is used in '_calcMaxLossMargin()' calculated the max loss of a given portfolio.
   * @param price Assumed scenario price.
   * @return payoff Net $ profit or loss of the portfolio given a settlement price.
   */
  function _calcPayoffAtPrice(IOption option, ExpiryHolding memory expiryHolding, uint price)
    internal
    pure
    returns (int payoff)
  {
    for (uint i; i < expiryHolding.options.length; i++) {
      payoff += option.getSettlementValue(
        expiryHolding.options[i].strike, expiryHolding.options[i].balance, price, expiryHolding.options[i].isCall
      );
    }
  }

  /**
   * @dev return index price for a market
   */
  function _getIndexPrice(uint marketId) internal view returns (int, uint) {
    (uint spot, uint confidence) = spotFeeds[marketId].getSpot();
    return (spot.toInt256(), confidence);
  }

  /**
   * @dev return the forward price for a specific market and expiry timestamp
   */
  function _getForwardPrice(uint marketId, uint expiry) internal view returns (int, uint) {
    (uint fwdPrice, uint confidence) = forwardFeeds[marketId].getForwardPrice(uint64(expiry));
    if (fwdPrice == 0) revert BM_NoForwardPrice();
    return (fwdPrice.toInt256(), confidence);
  }

  /**
   * @dev get the mark to market value of an option by querying the pricing module
   */
  function _getMarkToMarket(
    uint8 marketId,
    int amount,
    int forwardPrice,
    uint strike,
    uint expiry,
    uint vol,
    bool isCall
  ) internal view returns (int value) {
    IOptionPricing pricing = IOptionPricing(pricingModules[marketId]);

    IOptionPricing.Expiry memory expiryData = IOptionPricing.Expiry({
      secToExpiry: uint64(expiry - block.timestamp),
      forwardPrice: uint128(uint(forwardPrice)),
      discountFactor: 1e18
    });

    IOptionPricing.Option memory option =
      IOptionPricing.Option({strike: uint128(strike), vol: uint128(vol), amount: amount, isCall: isCall});

    return pricing.getOptionValue(expiryData, option);
  }
}
