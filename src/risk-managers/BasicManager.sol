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
import {ISingleExpiryPortfolio} from "src/interfaces/ISingleExpiryPortfolio.sol";
import {IOption} from "src/interfaces/IOption.sol";
import {IOptionPricing} from "src/interfaces/IOptionPricing.sol";
import {IChainlinkSpotFeed} from "src/interfaces/IChainlinkSpotFeed.sol";
import {IBasicManager} from "src/interfaces/IBasicManager.sol";
import {IFutureFeed} from "src/interfaces/IFutureFeed.sol";
import {ISettlementFeed} from "src/interfaces/ISettlementFeed.sol";

import {ISpotFeed} from "src/interfaces/ISpotFeed.sol";

import {BaseManager} from "./BaseManager.sol";

import "lyra-utils/arrays/UnorderedMemoryArray.sol";

import "src/libraries/StrikeGrouping.sol";

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

  /// @dev Pricing module to get option mark-to-market price
  IOptionPricing public pricing;

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
  mapping(uint marketId => IFutureFeed) public forwardFeeds;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(IAccounts accounts_, ICashAsset cashAsset_) BaseManager(accounts_, cashAsset_) {}

  ////////////////////////
  //    Admin-Only     //
  ///////////////////////

  /**
   * @notice Whitelist an asset to be used in Manager
   * @dev the basic manager only support option asset & perp asset
   */
  function whitelistAsset(IAsset _asset, uint8 _marketId, AssetType _type) external onlyOwner {
    // registered asset
    assetDetails[_asset] = AssetDetail({isWhitelisted: true, marketId: _marketId, assetType: _type});

    emit AssetWhitelisted(address(_asset), _marketId, _type);
  }

  /**
   * @notice Set the oracles for a market id
   */
  function setOraclesForMarket(
    uint8 marketId,
    ISpotFeed spotFeed,
    IFutureFeed forwardFeed,
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
    if (_mmRequirement > _imRequirement) revert BM_InvalidMarginRequirement();
    if (_mmRequirement == 0 || _mmRequirement >= 1e18) revert BM_InvalidMarginRequirement();
    if (_imRequirement >= 1e18) revert BM_InvalidMarginRequirement();

    perpMarginRequirements[marketId] = PerpMarginRequirements(_mmRequirement, _imRequirement);

    emit MarginRequirementsSet(marketId, _mmRequirement, _imRequirement);
  }

  /**
   * @notice Set the option margin parameters for an market
   */
  function setOptionMarginParameters(uint8 marketId, OptionMarginParameters calldata params) external onlyOwner {
    optionMarginParams[marketId] = OptionMarginParameters(
      params.baselineOptionIM, params.baselineOptionMM, params.minStaticMMRatio, params.minStaticIMRatio
    );

    emit OptionMarginParametersSet(
      marketId, params.baselineOptionIM, params.baselineOptionMM, params.minStaticMMRatio, params.minStaticIMRatio
    );
  }

  /**
   * @notice Set the pricing module
   * @param _pricing new pricing module
   */
  function setPricingModule(IOptionPricing _pricing) external onlyOwner {
    // todo: use this for mark-to-market
    pricing = IOptionPricing(_pricing);

    emit PricingModuleSet(address(_pricing));
  }

  ///////////////////////
  //   Account Hooks   //
  ///////////////////////

  /**
   * @notice Ensures new manager is valid.
   * @param newManager IManager to change account to.
   */
  function handleManagerChange(uint, IManager newManager) external view {
    if (!whitelistedManager[address(newManager)]) {
      revert BM_NotWhitelistManager();
    }
  }

  /**
   * @notice Ensures asset is valid and Max Loss margin is met.
   * @param accountId Account for which to check trade.
   */
  function handleAdjustment(uint accountId, uint, address, IAccounts.AssetDelta[] calldata assetDeltas, bytes memory)
    public
    override
    onlyAccounts
  {
    // check assets are only cash and perp
    for (uint i = 0; i < assetDeltas.length; i++) {
      // allow cash
      if (address(assetDeltas[i].asset) == address(cashAsset)) continue;

      AssetDetail memory detail = assetDetails[assetDeltas[i].asset];

      if (!detail.isWhitelisted) revert BM_UnsupportedAsset();

      if (detail.assetType == AssetType.Perpetual) {
        // settle perps if the user has perp position
        _settleAccountPerps(IPerpAsset(address(assetDeltas[i].asset)), accountId);
      }
    }

    int cashBalance = accounts.getBalance(accountId, cashAsset, 0);

    // todo: don't allow borrowing cash

    // check initial margin met
    int margin = _getMargin(accountId, false);

    // cash deposited has to cover net option margin + net perp margin
    if (cashBalance + margin < 0) {
      revert BM_PortfolioBelowMargin(accountId, -(margin));
    }
  }

  /**
   * @notice get the net margin for the option positions. This is expected to be negative
   * @param accountId Account Id for which to check
   */
  function _getMargin(uint accountId, bool isMaintenance) internal view returns (int margin) {
    // get portfolio from array of balances
    IAccounts.AssetBalance[] memory assetBalances = accounts.getAccountBalances(accountId);
    BasicManagerPortfolio memory portfolio = _arrangePortfolio(assetBalances);

    // for each subAccount, get margin and sum it up
    for (uint i = 0; i < portfolio.subAccounts.length; i++) {
      margin += _getSubAccountMargin(portfolio.subAccounts[i], isMaintenance);
    }
  }

  function _getSubAccountMargin(BasicManagerSubAccount memory subAccount, bool isMaintenance)
    internal
    view
    returns (int)
  {
    int indexPrice = spotFeeds[subAccount.marketId].getSpot().toInt256();

    int netPerpMargin = _getNetPerpMargin(subAccount, indexPrice, isMaintenance);
    int netOptionMargin = _getNetOptionMargin(subAccount, isMaintenance);
    return netPerpMargin + netOptionMargin;
  }

  /**
   * @notice get the margin required for the perp position of an subAccount
   * @return net margin for a perp position, always negative
   */
  function _getNetPerpMargin(BasicManagerSubAccount memory subAccount, int indexPrice, bool isMaintenance)
    internal
    view
    returns (int)
  {
    uint notional = subAccount.perpPosition.multiplyDecimal(indexPrice).abs();
    uint requirement = isMaintenance
      ? perpMarginRequirements[subAccount.marketId].mmRequirement
      : perpMarginRequirements[subAccount.marketId].imRequirement;
    int marginRequired = notional.multiplyDecimal(requirement).toInt256();
    return -marginRequired;
  }

  /**
   * @notice get the net margin for the option positions. This is expected to be negative
   */
  function _getNetOptionMargin(BasicManagerSubAccount memory subAccount, bool isMaintenance)
    internal
    view
    returns (int margin)
  {
    // for each expiry, sum up the margin requirement
    for (uint i = 0; i < subAccount.expiryHoldings.length; i++) {
      margin += _calcNetBasicMarginSingleExpiry(
        subAccount.marketId, subAccount.option, subAccount.expiryHoldings[i], isMaintenance
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
      BasicManagerPortfolio({cash: cashBalance, subAccounts: new BasicManagerSubAccount[](marketCount)});

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
      portfolio.subAccounts[i].marketId = marketId;

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
          portfolio.subAccounts[i].perp = IPerpAsset(address(currentAsset.asset));
          portfolio.subAccounts[i].perpPosition = currentAsset.balance;
        } else {
          portfolio.subAccounts[i].option = IOption(address(currentAsset.asset));
          (uint expiry,,) = OptionEncoding.fromSubId(uint96(currentAsset.subId));
          uint expiryIndex;
          (numExpires, expiryIndex) = seenExpires.addUniqueToArray(expiry, numExpires);
          // print all seen expiries
          expiryOptionCounts[expiryIndex]++;
        }
      }

      // 3. initiate expiry holdings the subAccount
      portfolio.subAccounts[i].expiryHoldings = new ExpiryHolding[](numExpires);
      // 4. initiate the option array in each expiry holding
      for (uint j; j < numExpires; j++) {
        portfolio.subAccounts[i].expiryHoldings[j].options = new Option[](expiryOptionCounts[j]);
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
          uint nextIndex = portfolio.subAccounts[i].expiryHoldings[expiryIndex].numOptions;
          portfolio.subAccounts[i].expiryHoldings[expiryIndex].options[nextIndex] =
            Option({strike: strike, isCall: isCall, balance: currentAsset.balance});

          portfolio.subAccounts[i].expiryHoldings[expiryIndex].numOptions++;
          if (isCall) {
            portfolio.subAccounts[i].expiryHoldings[expiryIndex].netCalls += currentAsset.balance;
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
    uint marketId,
    IOption option,
    ExpiryHolding memory expiryHolding,
    bool isMaintenance
  ) internal view returns (int margin) {
    bool lossBounded = expiryHolding.netCalls >= 0;

    int maxLossMargin = 0;
    int isolatedMargin = 0;
    bool zeroStrikeChecked;

    IFutureFeed feed = forwardFeeds[marketId];

    int forwardPrice = feed.getFuturePrice(expiryHolding.expiry).toInt256();

    for (uint i; i < expiryHolding.options.length; i++) {
      // calculate isolated margin for this strike, aggregate to isolatedMargin
      isolatedMargin += _getIsolatedMargin(
        marketId,
        expiryHolding.options[i].strike,
        expiryHolding.options[i].isCall,
        expiryHolding.options[i].balance,
        forwardPrice,
        isMaintenance
      );

      // only calculate the max loss margin if loss is bounded (net calls > 0)
      if (lossBounded) {
        uint scenarioPrice = expiryHolding.options[i].strike;
        maxLossMargin = SignedMath.min(_calcPayoffAtPrice(option, expiryHolding, scenarioPrice), maxLossMargin);
        if (scenarioPrice == 0) {
          zeroStrikeChecked = true;
        }
      }
    }

    // Ensure price = 0 scenario is always evaluated.
    if (lossBounded && !zeroStrikeChecked) {
      maxLossMargin = SignedMath.min(_calcPayoffAtPrice(option, expiryHolding, 0), maxLossMargin);
    }

    if (lossBounded) {
      return SignedMath.max(isolatedMargin, maxLossMargin);
    }

    return isolatedMargin;
  }

  /**
   * @notice Settle expired option positions in an account.
   * @dev This function can be called by anyone
   */
  function settleOptions(IOption option, uint accountId) external {
    if (!assetDetails[option].isWhitelisted) revert BM_UnsupportedAsset();
    _settleAccountOptions(option, accountId);
  }

  ////////////////////////
  //   View Functions   //
  ////////////////////////

  /**
   * @dev return the margin for an account, it means the account is insolvent
   */
  function getMargin(uint accountId, bool isMaintenance) external view returns (int) {
    return _getMargin(accountId, isMaintenance);
  }

  function getIsolatedMargin(uint8 marketId, uint strike, uint expiry, bool isCall, int balance, bool isMaintenance)
    external
    view
    returns (int)
  {
    int forwardPrice = forwardFeeds[marketId].getFuturePrice(expiry).toInt256();
    return _getIsolatedMargin(marketId, strike, isCall, balance, forwardPrice, isMaintenance);
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
    uint marketId,
    uint strike,
    bool isCall,
    int balance,
    int forwardPrice,
    bool isMaintenance
  ) internal view returns (int margin) {
    if (balance > 0) return 0;
    if (isCall) {
      margin = _getIsolatedMarginForCall(marketId, strike.toInt256(), balance, forwardPrice, isMaintenance);
    } else {
      margin = _getIsolatedMarginForPut(marketId, strike.toInt256(), balance, forwardPrice, isMaintenance);
    }
  }

  /**
   * @dev calculate isolated margin requirement for a put option
   * Basic Margin formula for Put:
   *     size * min(strike, max((B - OTM_amount/index), STATIC) * index)
   *     where:
   *        B is base line margin ratio.
   *        OTM_amount is index - strike
   *        STATIC is min static ratio.
   * @dev expected to return a negative number
   */
  function _getIsolatedMarginForPut(uint marketId, int strike, int amount, int index, bool isMaintenance)
    internal
    view
    returns (int)
  {
    int baseLine =
      isMaintenance ? optionMarginParams[marketId].baselineOptionMM : optionMarginParams[marketId].baselineOptionIM;
    int minStaticRatio =
      isMaintenance ? optionMarginParams[marketId].minStaticMMRatio : optionMarginParams[marketId].minStaticIMRatio;

    // this ratio become negative if option is ITM
    int otmRatio = (index - strike).divideDecimal(index);

    int margin = SignedMath.min(SignedMath.max(baseLine - otmRatio, minStaticRatio).multiplyDecimal(index), strike)
      .multiplyDecimal(amount);

    return margin;
  }

  /**
   * @dev calculate isolated margin requirement for a call option
   * Basic Margin formula for Call:
   *     size * max((B - OTM_amount / index), STATIC) * index
   *     where:
   *        B is base line margin ratio.
   *        OTM_amount is strike - index
   *        STATIC is min static ratio.
   * @param amount expected a negative number, representing amount of shorts
   */
  function _getIsolatedMarginForCall(uint marketId, int strike, int amount, int index, bool isMaintenance)
    internal
    view
    returns (int)
  {
    int baseLine =
      isMaintenance ? optionMarginParams[marketId].baselineOptionMM : optionMarginParams[marketId].baselineOptionIM;
    int minStaticRatio =
      isMaintenance ? optionMarginParams[marketId].minStaticMMRatio : optionMarginParams[marketId].minStaticIMRatio;

    // this ratio become negative if option is ITM
    int otmRatio = (strike - index).divideDecimal(index);

    int margin = SignedMath.max(baseLine - otmRatio, minStaticRatio).multiplyDecimal(index).multiplyDecimal(amount);

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

  ////////////////////////
  //      Modifiers     //
  ////////////////////////

  modifier onlyAccounts() {
    if (msg.sender != address(accounts)) revert BM_NotAccounts();
    _;
  }
}
