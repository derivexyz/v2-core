// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/math/SignedMath.sol";

import "lyra-utils/decimals/DecimalMath.sol";
import "lyra-utils/decimals/SignedDecimalMath.sol";
import "lyra-utils/math/IntLib.sol";
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

contract BasicManager is IBasicManager, BaseManager {
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

  /// @dev Mapping from marketId to spot price oracle
  mapping(uint marketId => ISpotFeed) public spotFeeds;

  /// @dev Mapping from marketId to settlement price oracle
  mapping(uint marketId => ISettlementFeed) public settlementFeeds;

  /// @dev Mapping from marketId to forward price oracle
  mapping(uint marketId => IForwardFeed) public forwardFeeds;

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
    IForwardFeed forwardFeed,
    ISettlementFeed settlementFeed
  ) external onlyOwner {
    // registered asset
    spotFeeds[marketId] = spotFeed;
    forwardFeeds[marketId] = forwardFeed;
    settlementFeeds[marketId] = settlementFeed;

    emit OraclesSet(marketId, address(spotFeed), address(forwardFeed), address(settlementFeed));
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
    address,
    IAccounts.AssetDelta[] calldata assetDeltas,
    bytes calldata managerData
  ) public override onlyAccounts {
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

    // if all trades are only reducing risk, return early
    if (isRiskReducing) return;

    int cashBalance = accounts.getBalance(accountId, cashAsset, 0);

    // the net margin here should always be zero or negative
    int initialMargin = _getMargin(accountId, true);

    // cash deposited has to cover net option margin + net perp margin
    if (cashBalance + initialMargin < 0) {
      revert BM_PortfolioBelowMargin(accountId, -(initialMargin));
    }
  }

  /**
   * @notice get the net margin for the option positions. This is expected to be negative
   * @param accountId Account Id for which to check
   */
  function _getMargin(uint accountId, bool isInitial) internal view returns (int margin) {
    // get portfolio from array of balances
    IAccounts.AssetBalance[] memory assetBalances = accounts.getAccountBalances(accountId);
    BasicManagerPortfolio memory portfolio = _arrangePortfolio(assetBalances);

    int depegMultiplier = _getDepegMultiplier(isInitial);

    // for each markets, get margin and sum it up
    for (uint i = 0; i < portfolio.marketHoldings.length; i++) {
      margin += _getMarketMargin(accountId, portfolio.marketHoldings[i], isInitial, depegMultiplier);
    }
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
    returns (int)
  {
    int indexPrice = _getIndexPrice(marketHolding.marketId);

    int netPerpMargin = _getNetPerpMargin(marketHolding, indexPrice, isInitial);
    int netOptionMargin = _getNetOptionMargin(marketHolding, indexPrice, isInitial);

    int depegMargin = 0;
    if (depegMultiplier != 0) {
      // depeg multiplier should be 0 for maintanance margin, or when there is no depeg
      int num = marketHolding.perpPosition.abs().toInt256() + marketHolding.numShortOptions;
      depegMargin = -num.multiplyDecimal(depegMultiplier).multiplyDecimal(indexPrice);
    }

    int unrealizedPerpPNL;
    if (marketHolding.perpPosition != 0) {
      // if _settlePerpRealizedPNL is called before this call, unrealized perp pnl should always be 0
      unrealizedPerpPNL = marketHolding.perp.getUnsettledAndUnrealizedCash(accountId);
    }

    return netPerpMargin + netOptionMargin + depegMargin + unrealizedPerpPNL;
  }

  /**
   * @notice get the margin required for the perp position of an market
   * @return net margin for a perp position, always negative
   */
  function _getNetPerpMargin(MarketHolding memory marketHolding, int indexPrice, bool isInitial)
    internal
    view
    returns (int)
  {
    uint notional = marketHolding.perpPosition.multiplyDecimal(indexPrice).abs();
    uint requirement = isInitial
      ? perpMarginRequirements[marketHolding.marketId].imRequirement
      : perpMarginRequirements[marketHolding.marketId].mmRequirement;
    int marginRequired = notional.multiplyDecimal(requirement).toInt256();
    return -marginRequired;
  }

  /**
   * @notice get the net margin for the option positions. This is expected to be negative
   */
  function _getNetOptionMargin(MarketHolding memory marketHolding, int indexPrice, bool isInitial)
    internal
    view
    returns (int margin)
  {
    // for each expiry, sum up the margin requirement
    for (uint i = 0; i < marketHolding.expiryHoldings.length; i++) {
      margin += _calcNetBasicMarginSingleExpiry(
        marketHolding.marketId, marketHolding.option, marketHolding.expiryHoldings[i], indexPrice, isInitial
      );
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

        // if it's perp asset, update the perp position directly
        if (detail.assetType == AssetType.Perpetual) {
          portfolio.marketHoldings[i].perp = IPerpAsset(address(currentAsset.asset));
          portfolio.marketHoldings[i].perpPosition = currentAsset.balance;
        } else {
          portfolio.marketHoldings[i].option = IOption(address(currentAsset.asset));
          (uint expiry,,) = OptionEncoding.fromSubId(uint96(currentAsset.subId));
          uint expiryIndex;
          (numExpires, expiryIndex) = seenExpires.addUniqueToArray(expiry, numExpires);
          // print all seen expiries
          expiryOptionCounts[expiryIndex]++;
        }
      }

      // 3. initiate expiry holdings in a marketHolding
      portfolio.marketHoldings[i].expiryHoldings = new ExpiryHolding[](numExpires);
      // 4. initiate the option array in each expiry holding
      for (uint j; j < numExpires; j++) {
        portfolio.marketHoldings[i].expiryHoldings[j].expiry = seenExpires[j];
        portfolio.marketHoldings[i].expiryHoldings[j].options = new Option[](expiryOptionCounts[j]);
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
            portfolio.marketHoldings[i].numShortOptions -= currentAsset.balance;
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
   * @return margin If the account's option require 10K cash, this function will return -10K
   */
  function _calcNetBasicMarginSingleExpiry(
    uint8 marketId,
    IOption option,
    ExpiryHolding memory expiryHolding,
    int indexPrice,
    bool isInitial
  ) internal view returns (int margin) {
    bool lossBounded = expiryHolding.netCalls >= 0;

    int maxLossMargin = 0;

    int isolatedMargin = 0;
    bool zeroStrikeChecked;

    int forwardPrice = _getForwardPrice(marketId, expiryHolding.expiry);

    for (uint i; i < expiryHolding.options.length; i++) {
      // calculate isolated margin for this strike, aggregate to isolatedMargin
      isolatedMargin += _getIsolatedMargin(
        marketId,
        expiryHolding.expiry,
        expiryHolding.options[i].strike,
        expiryHolding.options[i].isCall,
        expiryHolding.options[i].balance,
        indexPrice,
        forwardPrice,
        isInitial
      );

      // calculate the max loss margin, update the maxLossMargin if it's lower than current
      uint scenarioPrice = expiryHolding.options[i].strike;
      maxLossMargin = SignedMath.min(_calcPayoffAtPrice(option, expiryHolding, scenarioPrice), maxLossMargin);
      if (scenarioPrice == 0) {
        zeroStrikeChecked = true;
      }
    }

    // Ensure price = 0 scenario is always evaluated.
    if (lossBounded && !zeroStrikeChecked) {
      maxLossMargin = SignedMath.min(_calcPayoffAtPrice(option, expiryHolding, 0), maxLossMargin);
    }

    if (expiryHolding.netCalls < 0) {
      int unpairedScale = optionMarginParams[marketId].unpairedScale;
      maxLossMargin += expiryHolding.netCalls.multiplyDecimal(unpairedScale).multiplyDecimal(indexPrice);
    }

    // return the better of the 2 margins
    return SignedMath.max(isolatedMargin, maxLossMargin);
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
   * @dev return the margin requirement for an account
   *      if it is negative, it should be compared with cash balance to determine if the account is solvent or not.
   */
  function getMargin(uint accountId, bool isInitial) external view returns (int) {
    return _getMargin(accountId, isInitial);
  }

  function getIsolatedMargin(uint8 marketId, uint strike, uint expiry, bool isCall, int balance, bool isInitial)
    external
    view
    returns (int)
  {
    int indexPrice = _getIndexPrice(marketId);
    int forwardPrice = _getForwardPrice(marketId, expiry);
    return _getIsolatedMargin(marketId, expiry, strike, isCall, balance, indexPrice, forwardPrice, isInitial);
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
    uint strike,
    bool isCall,
    int balance,
    int indexPrice,
    int forwardPrice,
    bool isInitial
  ) internal view returns (int margin) {
    if (balance > 0) return 0;
    if (isCall) {
      margin =
        _getIsolatedMarginForCall(marketId, expiry, strike.toInt256(), balance, indexPrice, forwardPrice, isInitial);
    } else {
      margin =
        _getIsolatedMarginForPut(marketId, expiry, strike.toInt256(), balance, indexPrice, forwardPrice, isInitial);
    }
  }

  /**
   * @dev calculate isolated margin requirement for a put option
   * @dev expected to return a negative number
   */
  function _getIsolatedMarginForPut(
    uint8 marketId,
    uint expiry,
    int strike,
    int amount,
    int forwardPrice,
    int indexPrice,
    bool isInitial
  ) internal view returns (int) {
    // todo: get vol from vol oracle
    uint vol = 1e18;
    int markToMarket = _getMarkToMarket(marketId, amount, forwardPrice, strike, expiry, vol, false);

    OptionMarginParameters memory params = optionMarginParams[marketId];

    int maintenanceMargin = SignedMath.max(
      params.mmSPSpot.multiplyDecimal(indexPrice).multiplyDecimal(amount), params.mmSPMtm.multiplyDecimal(markToMarket)
    ) + markToMarket;

    if (!isInitial) return maintenanceMargin;

    int otmRatio = (indexPrice - strike).divideDecimal(indexPrice);
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
    uint expiry,
    int strike,
    int amount,
    int forwardPrice,
    int indexPrice,
    bool isInitial
  ) internal view returns (int) {
    uint vol = 1e18;
    int markToMarket = _getMarkToMarket(marketId, amount, forwardPrice, strike, expiry, vol, true);

    OptionMarginParameters memory params = optionMarginParams[marketId];

    if (!isInitial) {
      return (params.mmSCSpot.multiplyDecimal(indexPrice)).multiplyDecimal(amount) + markToMarket;
    }

    // this ratio become negative if option is ITM
    int otmRatio = (strike - indexPrice).divideDecimal(indexPrice);

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
  function _getIndexPrice(uint marketId) internal view returns (int indexPrice) {
    (uint spot,) = spotFeeds[marketId].getSpot();
    indexPrice = spot.toInt256();
  }

  /**
   * @dev return the forward price for a specific market and expiry timestamp
   */
  function _getForwardPrice(uint marketId, uint expiry) internal view returns (int) {
    (uint fwdPrice,) = forwardFeeds[marketId].getForwardPrice(expiry);
    if (fwdPrice == 0) revert BM_NoForwardPrice();
    return fwdPrice.toInt256();
  }

  /**
   * @dev get the mark to market value of an option by querying the pricing module
   */
  function _getMarkToMarket(
    uint8 marketId,
    int amount,
    int forwardPrice,
    int strike,
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
      IOptionPricing.Option({strike: uint128(uint(strike)), vol: uint128(vol), amount: amount, isCall: isCall});

    return pricing.getOptionValue(expiryData, option);
  }
}
