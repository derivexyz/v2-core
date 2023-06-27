// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/math/SignedMath.sol";
import "openzeppelin/utils/math/Math.sol";
import "openzeppelin/access/Ownable2Step.sol";

import "lyra-utils/decimals/DecimalMath.sol";
import "lyra-utils/decimals/SignedDecimalMath.sol";
import "lyra-utils/encoding/OptionEncoding.sol";
import "lyra-utils/arrays/UnorderedMemoryArray.sol";

import {ISubAccounts} from "../interfaces/ISubAccounts.sol";
import {IAsset} from "../interfaces/IAsset.sol";
import {ICashAsset} from "../interfaces/ICashAsset.sol";
import {IPerpAsset} from "../interfaces/IPerpAsset.sol";
import {IOption} from "../interfaces/IOption.sol";
import {IStandardManager} from "../interfaces/IStandardManager.sol";
import {IPortfolioViewer} from "../interfaces/IPortfolioViewer.sol";
import {IForwardFeed} from "../interfaces/IForwardFeed.sol";
import {IVolFeed} from "../interfaces/IVolFeed.sol";
import {ILiquidatableManager} from "../interfaces/ILiquidatableManager.sol";

import {ISettlementFeed} from "../interfaces/ISettlementFeed.sol";
import {IDutchAuction} from "../interfaces/IDutchAuction.sol";

import {ISpotFeed} from "../interfaces/ISpotFeed.sol";

import {IOptionPricing} from "../interfaces/IOptionPricing.sol";

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

  /// @dev Depeg IM parameters: use to increase margin requirement if USDC depeg
  DepegParams internal depegParams;

  /// @dev Oracle that returns USDC / USD price
  ISpotFeed internal stableFeed;

  /// @dev Portfolio viewer contract
  IPortfolioViewer internal viewer;

  /// @dev if turned on, people can borrow cash from standard manager, aka have negative balance.
  bool public borrowingEnabled;

  /// @dev True if an IAsset address is whitelisted.
  mapping(IAsset asset => AssetDetail) internal _assetDetails;

  /// @dev Perp Margin Requirements: maintenance and initial margin requirements
  mapping(uint marketId => PerpMarginRequirements) internal perpMarginRequirements;

  /// @dev Option Margin Parameters. See getIsolatedMargin for how it is used in the formula
  mapping(uint marketId => OptionMarginParams) internal optionMarginParams;

  /// @dev Base margin discount: each base asset be treated as "spot * discount_factor" amount of cash
  mapping(uint marketId => int) internal baseMarginDiscountFactor;

  /// @dev Oracle Contingency parameters. used to increase margin requirement if oracle has low confidence
  mapping(uint marketId => OracleContingencyParams) internal oracleContingencyParams;

  /// @dev Mapping from marketId to spot price oracle
  mapping(uint marketId => ISpotFeed) internal spotFeeds;

  /// @dev Mapping from marketId to settlement price oracle
  mapping(uint marketId => ISettlementFeed) internal settlementFeeds;

  /// @dev Mapping from marketId to forward price oracle
  mapping(uint marketId => IForwardFeed) internal forwardFeeds;

  /// @dev Mapping from marketId to vol oracle
  mapping(uint marketId => IVolFeed) internal volFeeds;

  /// @dev Mapping from marketId to forward price oracle
  mapping(uint marketId => IOptionPricing) internal pricingModules;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(ISubAccounts subAccounts_, ICashAsset cashAsset_, IDutchAuction _dutchAuction, IPortfolioViewer _viewer)
    BaseManager(subAccounts_, cashAsset_, _dutchAuction)
  {
    viewer = _viewer;
  }

  ////////////////////////
  //    Admin-Only     //
  ///////////////////////

  /**
   * @notice Whitelist an asset to be used in Manager
   * @dev the standard manager only support option asset & perp asset
   */
  function whitelistAsset(IAsset _asset, uint8 _marketId, AssetType _type) external onlyOwner {
    _assetDetails[_asset] = AssetDetail({isWhitelisted: true, marketId: _marketId, assetType: _type});

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
  function setOraclesForMarket(
    uint8 marketId,
    ISpotFeed spotFeed,
    IForwardFeed forwardFeed,
    ISettlementFeed settlementFeed,
    IVolFeed volFeed
  ) external onlyOwner {
    // registered asset
    spotFeeds[marketId] = spotFeed;
    forwardFeeds[marketId] = forwardFeed;
    settlementFeeds[marketId] = settlementFeed;
    volFeeds[marketId] = volFeed;

    emit OraclesSet(marketId, address(spotFeed), address(forwardFeed), address(settlementFeed), address(volFeed));
  }

  /**
   * @notice Set perp maintenance margin requirement for an market
   * @param _mmPerpReq new maintenance margin requirement
   * @param _imPerpReq new initial margin requirement
   */
  function setPerpMarginRequirements(uint8 marketId, uint _mmPerpReq, uint _imPerpReq) external onlyOwner {
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
  function setBaseMarginDiscountFactor(uint8 marketId, uint discountFactor) external onlyOwner {
    if (discountFactor >= 1e18) {
      revert SRM_InvalidBaseDiscountFactor();
    }

    baseMarginDiscountFactor[marketId] = int(discountFactor);

    emit BaseMarginDiscountFactorSet(marketId, discountFactor);
  }

  /**
   * @notice Set the option margin parameters for an market
   */
  function setOptionMarginParams(uint8 marketId, OptionMarginParams calldata params) external onlyOwner {
    if (
      params.maxSpotReq < 0 || params.maxSpotReq > 1.2e18 // 0 < x < 1.2
        || params.minSpotReq < 0 || params.minSpotReq > 1.2e18 // 0 < x < 1,2
        || params.mmCallSpotReq < 0 || params.mmCallSpotReq > 1e18 // 0 < x < 1
        || params.mmPutSpotReq < 0 || params.mmPutSpotReq > 1e18 // 0 < x < 1
        || params.MMPutMtMReq < 0 || params.MMPutMtMReq > 1e18 // 0 < x < 1
        || params.unpairedMMScale < 1e18 || params.unpairedMMScale > 3e18 // 1 < x < 3
        || params.unpairedIMScale < 1e18 || params.unpairedIMScale > 3e18 // 1 < x < 3
        || params.mmOffsetScale < 1e18 || params.mmOffsetScale > 3e18 // 1 < x < 3
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
  function setOracleContingencyParams(uint8 marketId, OracleContingencyParams calldata params) external onlyOwner {
    if (
      params.perpThreshold > 1e18 || params.optionThreshold > 1e18 || params.baseThreshold > 1e18
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
    ISubAccounts.AssetDelta[] calldata assetDeltas,
    bytes calldata managerData
  ) public override onlyAccounts {
    // check if account is valid
    _verifyCanTrade(accountId);

    // send data to oracles if needed
    _processManagerData(tradeId, managerData);

    _checkAllAssetCaps(accountId, tradeId);

    // if account is only reduce perp position, increasing cash, or increasing option position, bypass check
    bool isRiskReducing = true;

    // check assets are only cash or whitelisted perp and options
    for (uint i = 0; i < assetDeltas.length; i++) {
      // allow cash
      if (address(assetDeltas[i].asset) == address(cashAsset)) {
        if (assetDeltas[i].delta < 0) isRiskReducing = false;
        continue;
      }

      AssetDetail memory detail = _assetDetails[assetDeltas[i].asset];

      if (!detail.isWhitelisted) revert SRM_UnsupportedAsset();

      if (detail.assetType == AssetType.Perpetual) {
        IPerpAsset perp = IPerpAsset(address(assetDeltas[i].asset));
        // settle perp PNL into cash if the user traded perp in this tx.
        _settlePerpRealizedPNL(perp, accountId);

        if (isRiskReducing) {
          // check if the delta and position has same sign
          // if so, we cannot bypass the risk check
          int perpPosition = subAccounts.getBalance(accountId, perp, 0);
          if (perpPosition != 0 && assetDeltas[i].delta * perpPosition > 0) {
            isRiskReducing = false;
          }
        }
      } else if (detail.assetType == AssetType.Option) {
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

    _performRiskCheck(accountId, assetDeltas);
  }

  /**
   * @dev perform a risk check on the account.
   */
  function _performRiskCheck(uint accountId, ISubAccounts.AssetDelta[] memory assetDeltas) internal view {
    ISubAccounts.AssetBalance[] memory assetBalances = subAccounts.getAccountBalances(accountId);
    StandardManagerPortfolio memory portfolio = viewer.arrangeSRMPortfolio(assetBalances);

    // account can only have negative cash if borrowing is enabled
    if (!borrowingEnabled && portfolio.cash < 0) revert SRM_NoNegativeCash();

    // the net margin here should always be zero or negative, unless there is unrealized pnl from a perp that was not traded in this tx
    (int postIM,) = _getMarginAndMarkToMarket(accountId, portfolio, true);

    // cash deposited has to cover the margin requirement
    if (postIM < 0) {
      StandardManagerPortfolio memory prePortfolio =
        viewer.arrangeSRMPortfolio(_undoAssetDeltas(accountId, assetDeltas));

      (int preMM,) = _getMarginAndMarkToMarket(accountId, prePortfolio, false);
      (int postMM,) = _getMarginAndMarkToMarket(accountId, portfolio, false);

      // allow the trade to pass if the net margin increased (risk reduced)
      if (postMM > preMM) return;

      revert SRM_PortfolioBelowMargin(accountId, -(postIM));
    }
  }

  /**
   * @notice get the net margin for the option positions. This is expected to be negative
   * @param accountId Account Id for which to check
   * @return netMargin net margin. If negative, the account is under margin requirement
   * @return totalMarkToMarket the mark-to-market value of the portfolio, should be positive unless portfolio is obviously insolvent
   */
  function _getMarginAndMarkToMarket(uint accountId, StandardManagerPortfolio memory portfolio, bool isInitial)
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

    // base value is the mark to market value of ETH or BTC hold in the account
    (int baseMargin, int baseMtM) =
      _getBaseMarginAndMtM(marketHolding.marketId, marketHolding.basePosition, indexPrice, indexConf, isInitial);

    // apply depeg IM penalty
    if (depegMultiplier != 0) {
      // depeg multiplier should be 0 for maintenance margin, or when there is no depeg
      margin = -marketHolding.depegPenaltyPos.multiplyDecimal(depegMultiplier).multiplyDecimal(indexPrice);
    }

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
    (uint perpPrice, uint confidence) = marketHolding.perp.getPerpPrice();
    uint notional = SignedMath.abs(position).multiplyDecimal(perpPrice);
    uint requirement = isInitial
      ? perpMarginRequirements[marketHolding.marketId].imPerpReq
      : perpMarginRequirements[marketHolding.marketId].mmPerpReq;
    netMargin = -notional.multiplyDecimal(requirement).toInt256();

    if (!isInitial) return netMargin;

    // if the min of two confidences is below threshold, apply penalty (becomes more negative)
    uint minConf = Math.min(confidence, indexConf);
    OracleContingencyParams memory ocParam = oracleContingencyParams[marketHolding.marketId];
    if (ocParam.perpThreshold != 0 && minConf < ocParam.perpThreshold) {
      int diff = 1e18 - int(minConf);
      int penalty = diff.multiplyDecimal(ocParam.OCFactor).multiplyDecimal(indexPrice).multiplyDecimal(
        int(SignedMath.abs(position))
      );
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
    // for each expiry, sum up the margin requirement.
    // Also keep track of min confidence so we can apply oracle contingency on each expiry's bases
    for (uint i = 0; i < marketHolding.expiryHoldings.length; i++) {
      (int forwardPrice, uint localMin) =
        _getForwardPrice(marketHolding.marketId, marketHolding.expiryHoldings[i].expiry);
      localMin = Math.min(minConfidence, localMin);

      {
        uint volConf =
          volFeeds[marketHolding.marketId].getExpiryMinConfidence(uint64(marketHolding.expiryHoldings[i].expiry));
        localMin = Math.min(localMin, volConf);
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

      // add oracle contingency on this expiry if min conf is too low, only for IM
      if (!isInitial) continue;
      OracleContingencyParams memory ocParam = oracleContingencyParams[marketHolding.marketId];

      if (ocParam.optionThreshold != 0 && localMin < uint(ocParam.optionThreshold)) {
        int diff = 1e18 - int(localMin);
        int penalty = diff.multiplyDecimal(ocParam.OCFactor).multiplyDecimal(indexPrice).multiplyDecimal(
          marketHolding.expiryHoldings[i].totalShortPositions
        );
        netMargin -= penalty;
      }
    }
  }

  /**
   * @dev calculate the margin contributed by base asset, and the mark to market value
   */
  function _getBaseMarginAndMtM(uint8 marketId, int position, int indexPrice, uint indexConf, bool isInitial)
    internal
    view
    returns (int baseMargin, int baseMarkToMarket)
  {
    if (position == 0) return (0, 0);

    int discountFactor = baseMarginDiscountFactor[marketId];

    // the margin contributed by base asset is spot * positionSize * discount factor
    baseMargin = position.multiplyDecimal(discountFactor).multiplyDecimal(indexPrice);

    (uint usdcPrice,) = stableFeed.getSpot();
    // convert to denominate in USDC
    baseMarkToMarket = position.multiplyDecimal(indexPrice).divideDecimal(usdcPrice.toInt256());

    // add oracle contingency for spot asset, only for IM
    if (!isInitial) return (baseMargin, baseMarkToMarket);

    OracleContingencyParams memory ocParam = oracleContingencyParams[marketId];
    if (ocParam.baseThreshold != 0 && indexConf < uint(ocParam.baseThreshold)) {
      int diff = 1e18 - int(indexConf);
      int penalty = diff.multiplyDecimal(ocParam.OCFactor).multiplyDecimal(indexPrice).multiplyDecimal(position);
      baseMargin -= penalty;
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
    uint8 marketId,
    IOption option,
    ExpiryHolding memory expiryHolding,
    int indexPrice,
    int forwardPrice,
    bool isInitial
  ) internal view returns (int, int totalMarkToMarket) {
    // We make sure the evaluate the scenario at price = 0
    int maxLossMargin = _calcMaxLoss(option, expiryHolding, 0);
    int totalIsolatedMargin = 0;

    for (uint i; i < expiryHolding.options.length; i++) {
      Option memory optionPos = expiryHolding.options[i];

      // calculate isolated margin for this strike, aggregate to isolatedMargin
      (int isolatedMargin, int markToMarket) =
        _getIsolatedMargin(marketId, expiryHolding.expiry, optionPos, indexPrice, forwardPrice, isInitial);
      totalIsolatedMargin += isolatedMargin;
      totalMarkToMarket += markToMarket;

      // calculate the max loss margin, update the maxLossMargin if it's lower than current
      maxLossMargin = SignedMath.min(_calcMaxLoss(option, expiryHolding, optionPos.strike), maxLossMargin);
    }

    if (expiryHolding.netCalls < 0) {
      int unpairedScale =
        isInitial ? optionMarginParams[marketId].unpairedIMScale : optionMarginParams[marketId].unpairedMMScale;
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
    if (!_assetDetails[option].isWhitelisted) revert SRM_UnsupportedAsset();
    _settleAccountOptions(option, accountId);
  }

  /**
   * @dev settle perp value with index price
   */
  function settlePerpsWithIndex(IPerpAsset perp, uint accountId) external {
    if (!_assetDetails[perp].isWhitelisted) revert SRM_UnsupportedAsset();
    _settlePerpUnrealizedPNL(perp, accountId);
  }

  /**
   * @dev merge multiple standard accounts into one. A risk check is performed at the end to make sure it's valid
   * @param mergeIntoId the account id to merge into
   * @param mergeFromIds the account ids to merge from
   */
  function mergeAccounts(uint mergeIntoId, uint[] memory mergeFromIds) external {
    _mergeAccounts(mergeIntoId, mergeFromIds);

    // make sure ending account is solvent (above initial margin)
    _performRiskCheck(mergeIntoId, new ISubAccounts.AssetDelta[](0));
  }

  ////////////////////////
  //   View Functions   //
  ////////////////////////

  /**
   * @dev return the detail info of an asset. Should be empty if this is not trusted by standard manager
   */
  function assetDetails(IAsset asset) external view returns (AssetDetail memory) {
    return _assetDetails[asset];
  }

  /**
   * @dev return the total net margin of an account
   * @return margin if it is negative, the account is insolvent
   */
  function getMargin(uint accountId, bool isInitial) public view returns (int) {
    // get portfolio from array of balances
    ISubAccounts.AssetBalance[] memory assetBalances = subAccounts.getAccountBalances(accountId);
    StandardManagerPortfolio memory portfolio = viewer.arrangeSRMPortfolio(assetBalances);
    (int margin,) = _getMarginAndMarkToMarket(accountId, portfolio, isInitial);
    return margin;
  }

  /**
   * @dev the function used by the auction contract
   */
  function getMarginAndMarkToMarket(uint accountId, bool isInitial, uint) external view returns (int, int) {
    ISubAccounts.AssetBalance[] memory assetBalances = subAccounts.getAccountBalances(accountId);
    StandardManagerPortfolio memory portfolio = viewer.arrangeSRMPortfolio(assetBalances);
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

  function _chargeAllOIFee(address caller, uint accountId, uint tradeId, ISubAccounts.AssetDelta[] calldata assetDeltas)
    internal
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
        IOption option = IOption(address(assetDeltas[i].asset));
        IForwardFeed forwardFeed = forwardFeeds[detail.marketId];
        fee += _getOptionOIFee(option, forwardFeed, assetDeltas[i].delta, assetDeltas[i].subId, tradeId);
      }
    }

    _payFee(accountId, fee);
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
    OptionMarginParams memory params = optionMarginParams[marketId];

    int maintenanceMargin = SignedMath.min(
      params.mmPutSpotReq.multiplyDecimal(indexPrice).multiplyDecimal(amount),
      params.MMPutMtMReq.multiplyDecimal(markToMarket)
    ) + markToMarket;

    if (!isInitial) return maintenanceMargin;

    int otmRatio = SignedMath.max(indexPrice - strike.toInt256(), 0).divideDecimal(indexPrice);
    int imMultiplier = SignedMath.max(params.maxSpotReq - otmRatio, params.minSpotReq);

    int margin = SignedMath.min(
      imMultiplier.multiplyDecimal(indexPrice).multiplyDecimal(amount) + markToMarket,
      maintenanceMargin.multiplyDecimal(params.mmOffsetScale)
    );

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
    OptionMarginParams memory params = optionMarginParams[marketId];

    int maintenanceMargin = (params.mmCallSpotReq.multiplyDecimal(indexPrice)).multiplyDecimal(amount) + markToMarket;

    if (!isInitial) return maintenanceMargin;

    int otmRatio = SignedMath.max((strike.toInt256() - indexPrice), 0).divideDecimal(indexPrice);

    int imMultiplier = SignedMath.max(params.maxSpotReq - otmRatio, params.minSpotReq);

    int margin = (imMultiplier.multiplyDecimal(indexPrice)).multiplyDecimal(amount) + markToMarket;

    return margin;
  }

  /**
   * @notice Calculate the full portfolio payoff at a given settlement price.
   *         This is used in '_calcMaxLossMargin()' calculated the max loss of a given portfolio.
   * @param price Assumed scenario price.
   * @return payoff Net $ profit or loss of the portfolio given a settlement price.
   */
  function _calcMaxLoss(IOption option, ExpiryHolding memory expiryHolding, uint price)
    internal
    pure
    returns (int payoff)
  {
    for (uint i; i < expiryHolding.options.length; i++) {
      payoff += option.getSettlementValue(
        expiryHolding.options[i].strike, expiryHolding.options[i].balance, price, expiryHolding.options[i].isCall
      );
    }

    return SignedMath.min(payoff, 0);
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
    if (fwdPrice == 0) revert SRM_NoForwardPrice();
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

    uint64 secToExpiry = expiry > block.timestamp ? uint64(expiry - block.timestamp) : 0;

    IOptionPricing.Expiry memory expiryData =
      IOptionPricing.Expiry({secToExpiry: secToExpiry, forwardPrice: uint128(uint(forwardPrice)), discountFactor: 1e18});

    IOptionPricing.Option memory option =
      IOptionPricing.Option({strike: uint128(strike), vol: uint128(vol), amount: amount, isCall: isCall});

    return pricing.getOptionValue(expiryData, option);
  }
}
