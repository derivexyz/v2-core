// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/math/SignedMath.sol";
import "openzeppelin/utils/math/Math.sol";

import "lyra-utils/decimals/DecimalMath.sol";
import "lyra-utils/decimals/SignedDecimalMath.sol";
import "lyra-utils/arrays/UnorderedMemoryArray.sol";

import {ISubAccounts} from "../interfaces/ISubAccounts.sol";
import {IAsset} from "../interfaces/IAsset.sol";
import {ICashAsset} from "../interfaces/ICashAsset.sol";
import {IPerpAsset} from "../interfaces/IPerpAsset.sol";
import {IOptionAsset} from "../interfaces/IOptionAsset.sol";
import {IStandardManager} from "../interfaces/IStandardManager.sol";
import {ISRMPortfolioViewer} from "../interfaces/ISRMPortfolioViewer.sol";
import {IForwardFeed} from "../interfaces/IForwardFeed.sol";
import {IVolFeed} from "../interfaces/IVolFeed.sol";
import {ILiquidatableManager} from "../interfaces/ILiquidatableManager.sol";

import {IDutchAuction} from "../interfaces/IDutchAuction.sol";

import {ISpotFeed} from "../interfaces/ISpotFeed.sol";

import {IOptionPricing} from "../interfaces/IOptionPricing.sol";

import {IManager} from "../interfaces/IManager.sol";
import {BaseManager} from "./BaseManager.sol";

/**
 * @title StandardManager
 * @author Lyra
 * @notice Risk Manager that margin perp and option in isolation.
 */

contract StandardManager is IStandardManager, ILiquidatableManager, BaseManager {
  using SignedDecimalMath for int;
  using DecimalMath for uint;
  using SafeCast for uint;
  using SafeCast for int;
  using UnorderedMemoryArray for uint[];

  ///////////////
  // Variables //
  ///////////////

  /// @dev if turned on, people can borrow cash from standard manager, aka have negative balance.
  bool public borrowingEnabled;

  /// @dev Increasing Market Id
  uint public lastMarketId = 0;

  /// @dev Oracle that returns stable / USD price
  ISpotFeed public stableFeed;

  /// @dev Depeg IM parameters: use to increase margin requirement if stablecoin depegs
  DepegParams public depegParams;

  /// @dev True if an IAsset address is whitelisted.
  mapping(IAsset asset => AssetDetail) internal _assetDetails;

  /// @dev Mapping from marketId to asset type to IAsset address
  mapping(uint marketId => mapping(AssetType assetType => IAsset)) public assetMap;

  /// @dev Perp Margin Requirements: maintenance and initial margin requirements
  mapping(uint marketId => PerpMarginRequirements) public perpMarginRequirements;

  /// @dev Option Margin Parameters. See getIsolatedMargin for how it is used in the formula
  mapping(uint marketId => OptionMarginParams) public optionMarginParams;

  /// @dev Base margin discount: each base asset be treated as "spot * discount_factor" amount of cash
  mapping(uint marketId => uint) public baseMarginDiscountFactor;

  /// @dev Oracle Contingency parameters. used to increase margin requirement if oracle has low confidence
  mapping(uint marketId => OracleContingencyParams) public oracleContingencyParams;

  /// @dev Mapping from marketId to spot price oracle
  mapping(uint marketId => ISpotFeed) internal spotFeeds;

  /// @dev Mapping from marketId to forward price oracle
  mapping(uint marketId => IForwardFeed) internal forwardFeeds;

  /// @dev Mapping from marketId to vol oracle
  mapping(uint marketId => IVolFeed) internal volFeeds;

  /// @dev Mapping from marketId to forward price oracle
  mapping(uint marketId => IOptionPricing) internal pricingModules;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(
    ISubAccounts subAccounts_,
    ICashAsset cashAsset_,
    IDutchAuction _dutchAuction,
    ISRMPortfolioViewer _viewer
  ) BaseManager(subAccounts_, cashAsset_, _dutchAuction, _viewer) {}

  ///////////////////////
  //    Owner-Only     //
  ///////////////////////

  function createMarket(string calldata _marketName) external onlyOwner returns (uint marketId) {
    marketId = ++lastMarketId;
    emit MarketCreated(marketId, _marketName);
  }

  /**
   * @notice Whitelist an asset to be used in Manager
   * @dev the standard manager only support option asset & perp asset
   */
  function whitelistAsset(IAsset _asset, uint _marketId, AssetType _type) external onlyOwner {
    // TODO(anton): make sure you can't put the same asset on multiple markets/different types etc.
    _checkMarketExist(_marketId);

    IAsset previousAsset = assetMap[_marketId][_type];
    delete _assetDetails[previousAsset];

    _assetDetails[_asset] = AssetDetail({isWhitelisted: true, marketId: _marketId, assetType: _type});

    assetMap[_marketId][_type] = _asset;

    emit AssetWhitelisted(address(_asset), _marketId, _type);
  }

  /**
   * @notice enable borrowing (negative cash balance) for standard manager
   */
  function setBorrowingEnabled(bool enabled) external onlyOwner {
    borrowingEnabled = enabled;

    emit BorrowingEnabled(enabled);
  }

  /**
   * @notice Set the oracles for a market id
   */
  function setOraclesForMarket(uint marketId, ISpotFeed spotFeed, IForwardFeed forwardFeed, IVolFeed volFeed)
    external
    onlyOwner
  {
    _checkMarketExist(marketId);

    // registered asset
    spotFeeds[marketId] = spotFeed;
    forwardFeeds[marketId] = forwardFeed;
    volFeeds[marketId] = volFeed;

    emit OraclesSet(marketId, address(spotFeed), address(forwardFeed), address(volFeed));
  }

  /**
   * @notice Set perp maintenance margin requirement for an market
   * @param _mmPerpReq new maintenance margin requirement
   * @param _imPerpReq new initial margin requirement
   */
  function setPerpMarginRequirements(uint marketId, uint _mmPerpReq, uint _imPerpReq) external onlyOwner {
    _checkMarketExist(marketId);

    if (_mmPerpReq > _imPerpReq || _mmPerpReq == 0 || _mmPerpReq >= 1e18 || _imPerpReq >= 1e18) {
      revert SRM_InvalidPerpMarginParams();
    }

    perpMarginRequirements[marketId] = PerpMarginRequirements(_mmPerpReq, _imPerpReq);

    emit PerpMarginRequirementsSet(marketId, _mmPerpReq, _imPerpReq);
  }

  /**
   * @dev Set discount factor for base asset
   * @dev if this factor is 0 (unset), base asset won't contribute to margin
   */
  function setBaseMarginDiscountFactor(uint marketId, uint discountFactor) external onlyOwner {
    _checkMarketExist(marketId);

    if (discountFactor >= 1e18) {
      revert SRM_InvalidBaseDiscountFactor();
    }

    baseMarginDiscountFactor[marketId] = discountFactor;

    emit BaseMarginDiscountFactorSet(marketId, discountFactor);
  }

  /**
   * @notice Set the option margin parameters for an market
   */
  function setOptionMarginParams(uint marketId, OptionMarginParams calldata params) external onlyOwner {
    _checkMarketExist(marketId);

    if (
      params.maxSpotReq > 1.2e18 // 0 <= x <= 1.2
        || params.minSpotReq > 1.2e18 // 0 <= x <= 1.2
        || params.mmCallSpotReq > 1e18 // 0 <= x <= 1
        || params.mmPutSpotReq > 1e18 // 0 <= x <= 1
        || params.MMPutMtMReq > 1e18 // 0 <= x <= 1
        || params.unpairedMMScale < 1e18 || params.unpairedMMScale > 3e18 // 1 <= x <= 3
        || params.unpairedIMScale < 1e18 || params.unpairedIMScale > 3e18 // 1 <= x <= 3
        || params.mmOffsetScale < 1e18 || params.mmOffsetScale > 3e18 // 1 <= x <= 3
    ) {
      revert SRM_InvalidOptionMarginParams();
    }

    optionMarginParams[marketId] = params;

    emit OptionMarginParamsSet(
      marketId,
      params.maxSpotReq,
      params.minSpotReq,
      params.mmCallSpotReq,
      params.mmPutSpotReq,
      params.MMPutMtMReq,
      params.unpairedMMScale,
      params.unpairedIMScale,
      params.mmOffsetScale
    );
  }

  /**
   * @notice Set the option margin parameters for an market
   */
  function setOracleContingencyParams(uint marketId, OracleContingencyParams memory params) external onlyOwner {
    _checkMarketExist(marketId);
    if (
      params.perpThreshold > 1e18 //
        || params.optionThreshold > 1e18
      //
      || params.baseThreshold > 1e18
      //
      || params.OCFactor > 1e18
    ) {
      revert SRM_InvalidOracleContingencyParams();
    }
    oracleContingencyParams[marketId] = params;

    emit OracleContingencySet(params.perpThreshold, params.optionThreshold, params.baseThreshold, params.OCFactor);
  }

  /**
   * @notice Set the option margin parameters for an market
   *
   */
  function setDepegParameters(DepegParams calldata params) external onlyOwner {
    if (params.threshold > 1e18 || params.depegFactor > 3e18) revert SRM_InvalidDepegParams();
    depegParams = params;

    emit DepegParametersSet(params.threshold, params.depegFactor);
  }

  /**
   * @notice Set feed for stable / USD price
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
  function setPricingModule(uint marketId, IOptionPricing _pricing) external onlyOwner {
    _checkMarketExist(marketId);

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
    ISubAccounts.AssetDelta[] memory assetDeltas,
    bytes calldata managerData
  ) public override onlyAccounts {
    _preAdjustmentHooks(accountId, tradeId, caller, assetDeltas, managerData);

    // if account is only reduce perp position, increasing cash, or increasing option position, bypass check
    bool riskAdding = false;

    bool isPositiveCashDelta = true;

    // check assets are only cash or whitelisted perp and options
    for (uint i = 0; i < assetDeltas.length; i++) {
      if (address(assetDeltas[i].asset) == address(cashAsset)) {
        if (assetDeltas[i].delta < 0) {
          riskAdding = true;
          isPositiveCashDelta = false;
        }
        continue;
      }

      AssetDetail memory detail = _assetDetails[assetDeltas[i].asset];

      if (!detail.isWhitelisted) revert SRM_UnsupportedAsset();

      if (detail.assetType == AssetType.Perpetual) {
        IPerpAsset perp = IPerpAsset(address(assetDeltas[i].asset));
        // settle perp PNL into cash if the user traded perp in this tx.
        _settlePerpRealizedPNL(perp, accountId);

        if (!riskAdding) {
          // check if the delta and position has same sign
          // if so, we cannot bypass the risk check
          int perpPosition = subAccounts.getBalance(accountId, perp, 0);
          if (perpPosition != 0 && assetDeltas[i].delta * perpPosition > 0) {
            riskAdding = true;
          }
        }
      } else if (detail.assetType == AssetType.Option) {
        // if the user is shorting more options, we need to check margin
        if (assetDeltas[i].delta < 0) {
          riskAdding = true;
        }
      }
    }

    ISubAccounts.AssetBalance[] memory assetBalances = subAccounts.getAccountBalances(accountId);
    ISubAccounts.AssetBalance[] memory previousBalances = viewer.undoAssetDeltas(accountId, assetDeltas);

    // TODO: test max account size properly (risk adding = false allowed creating unliquidatable portfolios)
    if (assetBalances.length > maxAccountSize && previousBalances.length < assetBalances.length) {
      revert SRM_TooManyAssets();
    }

    // only bypass risk check if we are only reducing perp position, increasing cash, or increasing option position
    if (!riskAdding) return;

    _performRiskCheck(accountId, assetBalances, previousBalances, isPositiveCashDelta);
  }

  /**
   * @dev Perform a risk check on the account.
   */
  function _performRiskCheck(
    uint accountId,
    ISubAccounts.AssetBalance[] memory assetBalances,
    ISubAccounts.AssetBalance[] memory previousBalances,
    bool isPositiveCashDelta
  ) internal view {
    StandardManagerPortfolio memory portfolio = ISRMPortfolioViewer(address(viewer)).arrangeSRMPortfolio(assetBalances);

    // TODO: add tests that we allow people to have neg cash if they already had it previously (only close neg cash)
    // need to compare cash delta to previous balance -> if post_trade_cash < 0 -> delta can only be positive

    // account can only have negative cash if borrowing is enabled
    if (!borrowingEnabled && portfolio.cash < 0 && !isPositiveCashDelta) revert SRM_NoNegativeCash();

    // the net margin here should always be zero or negative, unless there is unrealized pnl from a perp that was not traded in this tx
    (int postIM,) = _getMarginAndMarkToMarket(accountId, portfolio, true);

    // cash deposited covers the IM requirement
    if (postIM >= 0) return;

    // otherwise we check that the risk of the portfolio (MM) improves
    StandardManagerPortfolio memory prePortfolio =
      ISRMPortfolioViewer(address(viewer)).arrangeSRMPortfolio(previousBalances);

    (int preMM,) = _getMarginAndMarkToMarket(accountId, prePortfolio, false);
    (int postMM,) = _getMarginAndMarkToMarket(accountId, portfolio, false);

    // allow the trade to pass if the net margin increased (risk reduced), and it is now above the solvent line
    if (postMM > preMM && postMM > 0) return;

    revert SRM_PortfolioBelowMargin();
  }

  /**
   * @notice Get the net margin for the option positions. This is expected to be negative
   * @param accountId Account Id for which to check
   * @return netMargin Net margin. If negative, the account is under margin requirement
   * @return totalMarkToMarket The mark-to-market value of the portfolio, should be positive unless portfolio is obviously insolvent
   */
  function _getMarginAndMarkToMarket(uint accountId, StandardManagerPortfolio memory portfolio, bool isInitial)
    internal
    view
    returns (int netMargin, int totalMarkToMarket)
  {
    uint depegMultiplier = _getDepegMultiplier(isInitial);

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
   * @dev If the stable feed for stable / USD return price lower than threshold, add extra amount to im
   * @return A positive multiplier that should be multiply to S * sum(shorts + perps)
   */
  function _getDepegMultiplier(bool isInitial) internal view returns (uint) {
    if (!isInitial) return 0;

    (uint stablePrice,) = stableFeed.getSpot();
    if (stablePrice >= depegParams.threshold) return 0;

    return (depegParams.threshold - stablePrice).multiplyDecimal(depegParams.depegFactor);
  }

  /**
   * @notice Return the margin for a specific market, including perp & option position
   * @dev This function should normally return a negative number, -100e18 means it requires $100 cash as margin
   *      it's possible that it return positive number because of unrealizedPNL from the perp position
   */
  function _getMarketMargin(uint accountId, MarketHolding memory marketHolding, bool isInitial, uint depegMultiplier)
    internal
    view
    returns (int margin, int markToMarket)
  {
    (uint spotPrice, uint spotConf) = _getSpotPrice(marketHolding.marketId);

    // also getting confidence because we need to find the
    int netPerpMargin = _getNetPerpMargin(marketHolding, spotPrice, isInitial, spotConf);
    (int netOptionMargin, int optionMtm) = _getNetOptionMarginAndMtM(marketHolding, spotPrice, isInitial, spotConf);

    // apply depeg IM penalty
    if (depegMultiplier != 0) {
      // depeg multiplier should be 0 for maintenance margin, or when there is no depeg
      margin = -(marketHolding.depegPenaltyPos.multiplyDecimal(depegMultiplier).multiplyDecimal(spotPrice).toInt256());
    }

    // base value is the mark to market value of ETH or BTC hold in the account
    (int baseMargin, int baseMtM) =
      _getBaseMarginAndMtM(marketHolding.marketId, marketHolding.basePosition, spotPrice, spotConf, isInitial);

    int unrealizedPerpPNL;
    if (marketHolding.perpPosition != 0) {
      // if this function is called in handleAdjustment, unrealized perp pnl will always be 0 if this perp is traded
      // because it would have been settled.
      // If called as a view function or on perp assets didn't got traded in this tx, it will represent the value that
      // should be added as cash if it is settle now
      unrealizedPerpPNL = marketHolding.perp.getUnsettledAndUnrealizedCash(accountId);
    }

    margin += (netPerpMargin + netOptionMargin + baseMargin + unrealizedPerpPNL);

    // unrealized pnl is the mark to market value of a perp position
    markToMarket = optionMtm + unrealizedPerpPNL + baseMtM;
  }

  /**
   * @notice Get the margin required for the perp position of an market
   * @param spotConf index confidence
   * @return netMargin for a perp position, always negative
   */
  function _getNetPerpMargin(MarketHolding memory marketHolding, uint spotPrice, bool isInitial, uint spotConf)
    internal
    view
    returns (int netMargin)
  {
    int position = marketHolding.perpPosition;
    if (position == 0) return 0;

    // while calculating margin for perp, we use the perp market price oracle
    (uint perpPrice, uint confidence) = marketHolding.perp.getPerpPrice();
    uint notional = SignedMath.abs(position).multiplyDecimal(perpPrice);
    uint requirement = isInitial
      ? perpMarginRequirements[marketHolding.marketId].imPerpReq
      : perpMarginRequirements[marketHolding.marketId].mmPerpReq;
    netMargin = -int(notional.multiplyDecimal(requirement));

    if (!isInitial) return netMargin;

    // if the min of two confidences is below threshold, apply penalty (becomes more negative)
    uint minConf = Math.min(confidence, spotConf);
    OracleContingencyParams memory ocParam = oracleContingencyParams[marketHolding.marketId];
    if (ocParam.perpThreshold != 0 && minConf < ocParam.perpThreshold) {
      uint diff = 1e18 - minConf;
      uint penalty =
        diff.multiplyDecimal(ocParam.OCFactor).multiplyDecimal(spotPrice).multiplyDecimal(SignedMath.abs(position));
      netMargin -= penalty.toInt256();
    }
  }

  /**
   * @notice Get the net margin for the option positions. This is expected to be negative
   * @param minConfidence minimum confidence of perp and index oracle. This will be used to compare with other oracles
   *        and if min of all confidence scores fall below a threshold, add a penalty to the margin
   */
  function _getNetOptionMarginAndMtM(
    MarketHolding memory marketHolding,
    uint spotPrice,
    bool isInitial,
    uint minConfidence
  ) internal view returns (int netMargin, int totalMarkToMarket) {
    // for each expiry, sum up the margin requirement.
    // Also keep track of min confidence so we can apply oracle contingency on each expiry's bases
    for (uint i = 0; i < marketHolding.expiryHoldings.length; i++) {
      (uint forwardPrice, uint localMinConf) =
        _getForwardPrice(marketHolding.marketId, marketHolding.expiryHoldings[i].expiry);
      localMinConf = Math.min(minConfidence, localMinConf);

      {
        uint volConf =
          volFeeds[marketHolding.marketId].getExpiryMinConfidence(uint64(marketHolding.expiryHoldings[i].expiry));
        localMinConf = Math.min(localMinConf, volConf);
      }

      (int margin, int mtm) = _calcNetBasicMarginSingleExpiry(
        marketHolding.marketId, marketHolding.expiryHoldings[i], spotPrice, forwardPrice, isInitial
      );
      netMargin += margin;
      totalMarkToMarket += mtm;

      // add oracle contingency on this expiry if min conf is too low, only for IM
      if (!isInitial) continue;
      OracleContingencyParams memory ocParam = oracleContingencyParams[marketHolding.marketId];

      if (ocParam.optionThreshold != 0 && localMinConf < uint(ocParam.optionThreshold)) {
        uint diff = 1e18 - localMinConf;
        uint penalty = diff.multiplyDecimal(ocParam.OCFactor).multiplyDecimal(spotPrice).multiplyDecimal(
          marketHolding.expiryHoldings[i].totalShortPositions
        );
        netMargin -= penalty.toInt256();
      }
    }
  }

  /**
   * @dev calculate the margin contributed by base asset, and the mark to market value
   */
  function _getBaseMarginAndMtM(uint marketId, uint position, uint spotPrice, uint spotConf, bool isInitial)
    internal
    view
    returns (int baseMargin, int baseMarkToMarket)
  {
    if (position == 0) return (0, 0);

    (uint stablePrice,) = stableFeed.getSpot();

    uint notional = position.multiplyDecimal(spotPrice);

    // the margin contributed by base asset is spot * positionSize * discount factor
    baseMargin = notional.multiplyDecimal(baseMarginDiscountFactor[marketId]).toInt256();

    // convert to denominate in stable
    baseMarkToMarket = notional.divideDecimal(stablePrice).toInt256();

    // add oracle contingency for spot asset, only for IM
    if (!isInitial) return (baseMargin, baseMarkToMarket);

    OracleContingencyParams memory ocParam = oracleContingencyParams[marketId];
    if (ocParam.baseThreshold != 0 && spotConf < uint(ocParam.baseThreshold)) {
      uint diff = 1e18 - spotConf;
      uint penalty = diff.multiplyDecimal(ocParam.OCFactor).multiplyDecimal(notional);
      baseMargin -= penalty.toInt256();
    }
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
    uint marketId,
    ExpiryHolding memory expiryHolding,
    uint spotPrice,
    uint forwardPrice,
    bool isInitial
  ) internal view returns (int, int totalMarkToMarket) {
    // We make sure the evaluate the scenario at price = 0
    int maxLossMargin = _calcMaxLoss(expiryHolding, 0);
    int totalIsolatedMargin = 0;

    for (uint i; i < expiryHolding.options.length; i++) {
      Option memory optionPos = expiryHolding.options[i];

      // calculate isolated margin for this strike, aggregate to isolatedMargin
      (int isolatedMargin, int markToMarket) =
        _getIsolatedMargin(marketId, expiryHolding.expiry, optionPos, spotPrice, forwardPrice, isInitial);
      totalIsolatedMargin += isolatedMargin;
      totalMarkToMarket += markToMarket;

      // calculate the max loss margin, update the maxLossMargin if it's lower than current
      maxLossMargin = SignedMath.min(_calcMaxLoss(expiryHolding, optionPos.strike), maxLossMargin);
    }

    if (expiryHolding.netCalls < 0) {
      uint unpairedScale =
        isInitial ? optionMarginParams[marketId].unpairedIMScale : optionMarginParams[marketId].unpairedMMScale;
      maxLossMargin += unpairedScale.multiplyDecimal(forwardPrice).toInt256().multiplyDecimal(expiryHolding.netCalls);
    }

    // return the better of the 2 as the margin
    return (SignedMath.max(totalIsolatedMargin, maxLossMargin), totalMarkToMarket);
  }

  /**
   * @notice Settle expired option positions in an account.
   * @dev This function can be called by anyone
   */
  function settleOptions(IOptionAsset option, uint accountId) external {
    if (!_assetDetails[option].isWhitelisted) revert SRM_UnsupportedAsset();
    _settleAccountOptions(option, accountId);
  }

  /**
   * @dev settle perp value with index price
   */
  function settlePerpsWithIndex(uint accountId) external {
    for (uint id = 1; id <= lastMarketId; id++) {
      IPerpAsset perp = IPerpAsset(address(assetMap[id][AssetType.Perpetual]));
      if (address(perp) == address(0) || subAccounts.getBalance(accountId, perp, 0) == 0) continue;
      _settlePerpUnrealizedPNL(perp, accountId);
    }
  }

  ////////////////////////
  //   View Functions   //
  ////////////////////////

  /**
   * @dev Return the detail info of an asset. Should be empty if this is not trusted by standard manager
   */
  function assetDetails(IAsset asset) external view returns (AssetDetail memory) {
    return _assetDetails[asset];
  }

  /**
   * @dev Return the addresses of feeds and pricing modules for a specific market
   */
  function getMarketFeeds(uint marketId) external view returns (ISpotFeed, IForwardFeed, IVolFeed, IOptionPricing) {
    return (spotFeeds[marketId], forwardFeeds[marketId], volFeeds[marketId], pricingModules[marketId]);
  }

  /**
   * @dev Return the total net margin of an account
   * @return margin if it is negative, the account is insolvent
   */
  function getMargin(uint accountId, bool isInitial) public view returns (int margin) {
    // get portfolio from array of balances
    StandardManagerPortfolio memory portfolio = ISRMPortfolioViewer(address(viewer)).getSRMPortfolio(accountId);
    (margin,) = _getMarginAndMarkToMarket(accountId, portfolio, isInitial);
    return margin;
  }

  /**
   * @dev Return the total net margin and MtM in one function call
   */
  function getMarginAndMarkToMarket(uint accountId, bool isInitial, uint)
    external
    view
    returns (int margin, int markToMarket)
  {
    StandardManagerPortfolio memory portfolio = ISRMPortfolioViewer(address(viewer)).getSRMPortfolio(accountId);
    return _getMarginAndMarkToMarket(accountId, portfolio, isInitial);
  }

  /**
   * @dev Return the isolated margin for a single option position
   * @return margin negative number, indicate margin requirement for a position
   * @return markToMarket the estimated worth of this position
   */
  function getIsolatedMargin(uint marketId, uint strike, uint expiry, bool isCall, int balance, bool isInitial)
    external
    view
    returns (int margin, int markToMarket)
  {
    (uint spotPrice,) = _getSpotPrice(marketId);
    (uint forwardPrice,) = _getForwardPrice(marketId, expiry);
    Option memory optionPos = Option({strike: strike, isCall: isCall, balance: balance});
    return _getIsolatedMargin(marketId, expiry, optionPos, spotPrice, forwardPrice, isInitial);
  }

  //////////////////////////
  //       Internal       //
  //////////////////////////

  function _checkMarketExist(uint marketId) internal view {
    if (marketId > lastMarketId) revert SRM_MarketNotCreated();
  }

  function _chargeAllOIFee(address caller, uint accountId, uint tradeId, ISubAccounts.AssetDelta[] memory assetDeltas)
    internal
    override
  {
    if (feeBypassedCaller[caller]) return;

    uint fee;
    // iterate through all asset changes, if it's option asset, change if OI increased
    for (uint i; i < assetDeltas.length; i++) {
      AssetDetail memory detail = _assetDetails[assetDeltas[i].asset];
      if (detail.assetType == AssetType.Perpetual) {
        IPerpAsset perp = IPerpAsset(address(assetDeltas[i].asset));
        fee += _getPerpOIFee(perp, assetDeltas[i].delta, tradeId);
      } else if (detail.assetType == AssetType.Option) {
        IOptionAsset option = IOptionAsset(address(assetDeltas[i].asset));
        IForwardFeed forwardFeed = forwardFeeds[detail.marketId];
        fee += _getOptionOIFee(option, forwardFeed, assetDeltas[i].delta, assetDeltas[i].subId, tradeId);
      }
    }

    _payFee(accountId, fee);
  }

  /**
   * @dev Calculate isolated margin requirement for a given number of calls and puts
   */
  function _getIsolatedMargin(
    uint marketId,
    uint expiry,
    Option memory optionPos,
    uint spotPrice,
    uint forwardPrice,
    bool isInitial
  ) internal view returns (int margin, int markToMarket) {
    (uint vol,) = volFeeds[marketId].getVol(uint128(optionPos.strike), uint64(expiry));
    markToMarket =
      _getMarkToMarket(marketId, optionPos.balance, forwardPrice, optionPos.strike, expiry, vol, optionPos.isCall);

    // a long position doesn't have any "margin", cannot be used to offset other positions
    if (optionPos.balance > 0) return (margin, markToMarket);

    if (optionPos.isCall) {
      margin =
        _getIsolatedMarginForCall(marketId, markToMarket, optionPos.strike, optionPos.balance, spotPrice, isInitial);
    } else {
      margin =
        _getIsolatedMarginForPut(marketId, markToMarket, optionPos.strike, optionPos.balance, spotPrice, isInitial);
    }
  }

  /**
   * @notice Calculate isolated margin requirement for a put option
   * @param amount Expected a negative number, representing amount of shorts
   *
   * @return Expected a negative number. Indicating how much cash is required to open this position in isolation
   */
  function _getIsolatedMarginForPut(
    uint marketId,
    int markToMarket,
    uint strike,
    int amount,
    uint spotPrice,
    bool isInitial
  ) internal view returns (int) {
    OptionMarginParams memory params = optionMarginParams[marketId];

    int maintenanceMargin = SignedMath.min(
      params.mmPutSpotReq.multiplyDecimal(spotPrice).toInt256().multiplyDecimal(amount),
      params.MMPutMtMReq.toInt256().multiplyDecimal(markToMarket)
    ) + markToMarket;

    if (!isInitial) return maintenanceMargin;

    uint otmRatio = 0;
    if (spotPrice > strike) {
      otmRatio = (spotPrice - strike).divideDecimal(spotPrice);
    }
    uint imMultiplier = params.minSpotReq;
    if (params.maxSpotReq > otmRatio && params.maxSpotReq - otmRatio > params.minSpotReq) {
      imMultiplier = params.maxSpotReq - otmRatio;
    }
    imMultiplier = imMultiplier.multiplyDecimal(spotPrice);

    int margin = SignedMath.min(
      imMultiplier.toInt256().multiplyDecimal(amount) + markToMarket,
      maintenanceMargin.multiplyDecimal(params.mmOffsetScale.toInt256())
    );
    return margin;
  }

  /**
   * @dev Calculate isolated margin requirement for a call option
   * @param amount Expected a negative number, representing amount of shorts
   *
   * @return Expected a negative number. Indicating how much cash is required to open this position in isolation
   */
  function _getIsolatedMarginForCall(
    uint marketId,
    int markToMarket,
    uint strike,
    int amount,
    uint spotPrice,
    bool isInitial
  ) internal view returns (int) {
    OptionMarginParams memory params = optionMarginParams[marketId];

    if (!isInitial) {
      int mmReqAdd = params.mmCallSpotReq.multiplyDecimal(spotPrice).toInt256().multiplyDecimal(amount);
      return markToMarket + mmReqAdd;
    }

    uint otmRatio = 0;
    if (strike > spotPrice) {
      otmRatio = (strike - spotPrice).divideDecimal(spotPrice);
    }

    uint imMultiplier = params.minSpotReq;
    if (params.maxSpotReq > otmRatio && params.maxSpotReq - otmRatio > params.minSpotReq) {
      imMultiplier = params.maxSpotReq - otmRatio;
    }
    imMultiplier = imMultiplier.multiplyDecimal(spotPrice);

    return imMultiplier.toInt256().multiplyDecimal(amount) + markToMarket;
  }

  /**
   * @notice Calculate the full portfolio payoff at a given settlement price.
   *         This is used in '_calcMaxLossMargin()' calculated the max loss of a given portfolio.
   * @param price Assumed scenario price.
   * @return payoff Net profit or loss of the portfolio in cash, given a settlement price.
   */
  function _calcMaxLoss(ExpiryHolding memory expiryHolding, uint price) internal pure returns (int payoff) {
    for (uint i; i < expiryHolding.options.length; i++) {
      payoff += _getSettlementValue(
        expiryHolding.options[i].strike, expiryHolding.options[i].balance, price, expiryHolding.options[i].isCall
      );
    }

    return SignedMath.min(payoff, 0);
  }

  /**
   * @dev Return index price for a market
   */
  function _getSpotPrice(uint marketId) internal view returns (uint, uint) {
    return spotFeeds[marketId].getSpot();
  }

  /**
   * @dev Return the forward price for a specific market and expiry timestamp
   */
  function _getForwardPrice(uint marketId, uint expiry) internal view returns (uint, uint) {
    (uint fwdPrice, uint confidence) = forwardFeeds[marketId].getForwardPrice(uint64(expiry));
    if (fwdPrice == 0) revert SRM_NoForwardPrice();
    return (fwdPrice, confidence);
  }

  /**
   * @dev Get the mark to market value of an option by querying the pricing module
   */
  function _getMarkToMarket(
    uint marketId,
    int amount,
    uint forwardPrice,
    uint strike,
    uint expiry,
    uint vol,
    bool isCall
  ) internal view returns (int value) {
    IOptionPricing pricing = IOptionPricing(pricingModules[marketId]);

    uint64 secToExpiry = expiry > block.timestamp ? uint64(expiry - block.timestamp) : 0;

    IOptionPricing.Expiry memory expiryData =
      IOptionPricing.Expiry({secToExpiry: secToExpiry, forwardPrice: forwardPrice.toUint128(), discountFactor: 1e18});

    IOptionPricing.Option memory option =
      IOptionPricing.Option({strike: strike.toUint128(), vol: vol.toUint128(), amount: amount, isCall: isCall});

    return pricing.getOptionValue(expiryData, option);
  }

  // strike per expiry
  function _getSettlementValue(uint strikePrice, int balance, uint settlementPrice, bool isCall)
    internal
    pure
    returns (int)
  {
    int priceDiff = settlementPrice.toInt256() - strikePrice.toInt256();

    if (isCall && priceDiff > 0) {
      // ITM Call
      return priceDiff.multiplyDecimal(balance);
    } else if (!isCall && priceDiff < 0) {
      // ITM Put
      return -priceDiff.multiplyDecimal(balance);
    } else {
      // OTM
      return 0;
    }
  }
}
