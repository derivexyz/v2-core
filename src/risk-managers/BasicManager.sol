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

import {BaseManager} from "./BaseManager.sol";

import "src/libraries/StrikeGrouping.sol";
import "src/libraries/BasicManagerPortfolioLib.sol";

import "forge-std/console2.sol";

/**
 * @title BasicManager
 * @author Lyra
 * @notice Risk Manager that margin in perp, cash and option in isolation.
 */

contract BasicManager is IBasicManager, BaseManager {
  using SignedDecimalMath for int;
  using DecimalMath for uint;
  using SafeCast for uint;
  using IntLib for int;
  using BasicManagerPortfolioLib for BasicManagerPortfolio;

  ///////////////
  // Variables //
  ///////////////

  uint constant MAX_STRIKES = 64;

  /// @dev Future feed oracle to get future price for an expiry
  IChainlinkSpotFeed public immutable feed;

  /// @dev Option asset address
  IOption public immutable option;

  /// @dev Perp asset address
  IPerpAsset public immutable perp;

  /// @dev Pricing module to get option mark-to-market price
  IOptionPricing public pricing;

  /// @dev Perp Margin Requirements: maintenance and initial margin requirements
  PerpMarginRequirements public perpMarginRequirements;

  /// @dev Option Margin Parameters. See getIsolatedMargin for how it is used in the formula
  OptionMarginParameters public optionMarginParams;

  /// @dev if an IAsset address is whitelisted.
  mapping(address => bool) public isWhitelisted;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(
    IAccounts accounts_,
    ICashAsset cashAsset_,
    IOption option_,
    IPerpAsset perp_,
    IFutureFeed futureFeed_,
    ISettlementFeed settlementFeed_,
    IChainlinkSpotFeed spotFeed_
  )
    // todo: update forward feed to use a new feed instead of spot
    BaseManager(accounts_, futureFeed_, settlementFeed_, cashAsset_)
  {
    feed = spotFeed_;
    option = option_;
    perp = perp_;
  }

  ////////////////////////
  //    Admin-Only     //
  ///////////////////////

  function whitelistAsset(address _asset) external onlyOwner {
    // registered asset
    isWhitelisted[_asset] = true;
  }

  /**
   * @notice Set the maintenance margin requirement
   * @param _mmRequirement new maintenance margin requirement
   * @param _imRequirement new initial margin requirement
   */
  function setPerpMarginRequirements(uint _mmRequirement, uint _imRequirement) external onlyOwner {
    if (_mmRequirement > _imRequirement) revert PM_InvalidMarginRequirement();
    if (_mmRequirement == 0 || _mmRequirement >= 1e18) revert PM_InvalidMarginRequirement();
    if (_imRequirement >= 1e18) revert PM_InvalidMarginRequirement();

    perpMarginRequirements = PerpMarginRequirements(_mmRequirement, _imRequirement);

    emit MarginRequirementsSet(_mmRequirement, _imRequirement);
  }

  /**
   * @notice Set the option margin parameters
   */
  function setOptionMarginParameters(OptionMarginParameters calldata params) external onlyOwner {
    optionMarginParams = OptionMarginParameters(
      params.baselineOptionIM, params.baselineOptionMM, params.minStaticMMRatio, params.minStaticIMRatio
    );

    emit OptionMarginParametersSet(
      params.baselineOptionIM, params.baselineOptionMM, params.minStaticMMRatio, params.minStaticIMRatio
    );
  }

  /**
   * @notice Set the pricing module
   * @param _pricing new pricing module
   */
  function setPricingModule(IOptionPricing _pricing) external onlyOwner {
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
      revert PM_NotWhitelistManager();
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
      if (!isWhitelisted[address(assetDeltas[i].asset)]) revert PM_UnsupportedAsset();

      IAsset.AssetType assetType = assetDeltas[i].asset.assetType();

      if (assetType == IAsset.AssetType.Perpetual) {
        // settle perps if the user has perp position
        _settleAccountPerps(IPerpAsset(address(assetDeltas[i].asset)), accountId);
      }
    }

    int indexPrice = feed.getSpot().toInt256();

    int cashBalance = accounts.getBalance(accountId, cashAsset, 0);

    // todo: don't allow borrowing cash

    int netPerpMargin = _getNetPerpMargin(accountId, indexPrice);
    int netOptionMargin = _getNetOptionMargin(accountId);

    // cash deposited has to cover net option margin + net perp margin
    if (cashBalance + netPerpMargin + netOptionMargin < 0) {
      revert PM_PortfolioBelowMargin(accountId, -(netPerpMargin + netOptionMargin));
    }
  }

  /**
   * @notice get the margin required for the perp position
   * @param accountId Account Id for which to check
   * @return net margin for a perp position, always negative
   */
  function _getNetPerpMargin(uint accountId, int indexPrice) internal view returns (int) {
    uint notional = accounts.getBalance(accountId, perp, 0).multiplyDecimal(indexPrice).abs();
    int marginRequired = notional.multiplyDecimal(perpMarginRequirements.imRequirement).toInt256();
    return -marginRequired;
  }

  /**
   * @notice get the net margin for the option positions. This is expected to be negative
   * @param accountId Account Id for which to check
   */
  function _getNetOptionMargin(uint accountId) internal view returns (int margin) {
    BasicManagerPortfolio memory portfolio = _arrangePortfolio(accounts.getAccountBalances(accountId));

    // margin = _calcNetBasicMargin(portfolio);
    // todo: 2 arrays to calculate _calcNetBasicMarginSingleExpiry() for all expiry
  }

  /**
   * @notice Arrange portfolio into cash + arranged
   *         array of [strikes][calls / puts].
   *         Unlike PCRM, the forwards are purposefully not filtered.
   * @param assets Array of balances for given asset and subId.
   * @return portfolio Cash + option holdings.
   */
  function _arrangePortfolio(IAccounts.AssetBalance[] memory assets)
    internal
    view
    returns (BasicManagerPortfolio memory portfolio)
  {
    IAccounts.AssetBalance memory currentAsset;
    for (uint i; i < assets.length; ++i) {
      currentAsset = assets[i];
      // if asset is cash, update cash balance
      if (address(currentAsset.asset) == address(cashAsset)) {
        portfolio.cash = currentAsset.balance;
        continue;
      }

      // else, it must be perp or option for one of the registered assets
      IAsset.AssetType assetType = currentAsset.asset.assetType();
      uint underlyingId = currentAsset.asset.underlyingId();

      if (assetType == IAsset.AssetType.Perpetual) {
        portfolio.addPerpToPortfolio(underlyingId, currentAsset.balance);
      } else if (assetType == IAsset.AssetType.Option) {
        portfolio.addOptionToPortfolio(underlyingId, uint96(currentAsset.subId), currentAsset.balance);
      }
    }
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
  function _calcNetBasicMarginSingleExpiry(OptionPortfolioSingleExpiry memory expiryHolding)
    internal
    view
    returns (int margin)
  {
    // todo: calculate each sub-portfolio with diff expiry and sum them all.

    // calculate total net calls. If net call > 0, then max loss is bounded when spot goes to infinity
    int netCalls;
    for (uint i; i < expiryHolding.numStrikesHeld; i++) {
      netCalls += expiryHolding.strikes[i].calls;
    }
    bool lossBounded = netCalls >= 0;

    int maxLossMargin = 0;
    int isolatedMargin = 0;
    bool zeroStrikeOwnable2Step;

    for (uint i; i < expiryHolding.numStrikesHeld; i++) {
      int forwardPrice = feed.getFuturePrice(expiryHolding.expiry).toInt256();

      // only calculate the max loss margin if loss is bounded (net calls > 0)
      if (lossBounded) {
        uint scenarioPrice = expiryHolding.strikes[i].strike;
        maxLossMargin = SignedMath.min(_calcPayoffAtPrice(expiryHolding, scenarioPrice), maxLossMargin);
        if (scenarioPrice == 0) {
          zeroStrikeOwnable2Step = true;
        }
      }

      // calculate isolated margin for this strike, aggregate to isolatedMargin
      isolatedMargin += _getIsolatedMargin(
        expiryHolding.strikes[i].strike,
        expiryHolding.strikes[i].calls,
        expiryHolding.strikes[i].puts,
        forwardPrice,
        false // is maintenance = false
      );
    }

    // Ensure $0 scenario is always evaluated.
    if (lossBounded && !zeroStrikeOwnable2Step) {
      maxLossMargin = SignedMath.min(_calcPayoffAtPrice(expiryHolding, 0), maxLossMargin);
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
  function settleOptions(uint accountId) external {
    _settleAccountOptions(option, accountId);
  }

  /**
   * @notice Settle accounts in batch
   * @dev This function can be called by anyone
   */
  function batchSettleAccounts(uint[] calldata accountIds) external {
    for (uint i; i < accountIds.length; ++i) {
      _settleAccountOptions(option, accountIds[i]);
    }
  }

  ////////////////////////
  //   View Functions   //
  ////////////////////////

  function getIsolatedMargin(uint strike, uint expiry, int calls, int puts, bool isMaintenance)
    external
    view
    returns (int)
  {
    int forwardPrice = feed.getFuturePrice(expiry).toInt256();
    return _getIsolatedMargin(strike, calls, puts, forwardPrice, isMaintenance);
  }

  /**
   * @dev calculate isolated margin requirement for a given number of calls and puts
   */
  function _getIsolatedMargin(uint strike, int calls, int puts, int forwardPrice, bool isMaintenance)
    internal
    view
    returns (int margin)
  {
    if (calls < 0) {
      margin += _getIsolatedMarginForCall(strike.toInt256(), calls, forwardPrice, isMaintenance);
    }
    if (puts < 0) {
      margin += _getIsolatedMarginForPut(strike.toInt256(), puts, forwardPrice, isMaintenance);
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
  function _getIsolatedMarginForPut(int strike, int amount, int index, bool isMaintenance) internal view returns (int) {
    int baseLine = isMaintenance ? optionMarginParams.baselineOptionMM : optionMarginParams.baselineOptionIM;
    int minStaticRatio = isMaintenance ? optionMarginParams.minStaticMMRatio : optionMarginParams.minStaticIMRatio;

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
  function _getIsolatedMarginForCall(int strike, int amount, int index, bool isMaintenance) internal view returns (int) {
    int baseLine = isMaintenance ? optionMarginParams.baselineOptionMM : optionMarginParams.baselineOptionIM;
    int minStaticRatio = isMaintenance ? optionMarginParams.minStaticMMRatio : optionMarginParams.minStaticIMRatio;

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
  function _calcPayoffAtPrice(OptionPortfolioSingleExpiry memory expiryHolding, uint price)
    internal
    view
    returns (int payoff)
  {
    for (uint i; i < expiryHolding.numStrikesHeld; i++) {
      ISingleExpiryPortfolio.Strike memory currentStrike = expiryHolding.strikes[i];
      payoff += option.getSettlementValue(currentStrike.strike, currentStrike.calls, price, true);
      payoff += option.getSettlementValue(currentStrike.strike, currentStrike.puts, price, false);
    }
  }

  /**
   * @notice Todo: change this function to work with multiple asset / expiries
   */
  function _addOption(ISingleExpiryPortfolio.Portfolio memory portfolio, IAccounts.AssetBalance memory asset)
    internal
    pure
    returns (uint addedStrikeIndex)
  {
    // decode subId
    (uint expiry, uint strikePrice, bool isCall) = OptionEncoding.fromSubId(SafeCast.toUint96(asset.subId));

    // assume expiry = 0 means this is the first strike.
    if (portfolio.expiry == 0) {
      portfolio.expiry = expiry;
    }

    if (portfolio.expiry != expiry) {
      revert("basic manager portfolio: multiple expiry!");
    }

    // add strike in-memory to portfolio
    (addedStrikeIndex, portfolio.numStrikesHeld) =
      StrikeGrouping.findOrAddStrike(portfolio.strikes, strikePrice, portfolio.numStrikesHeld);

    // add call or put balance
    if (isCall) {
      portfolio.strikes[addedStrikeIndex].calls += asset.balance;
    } else {
      portfolio.strikes[addedStrikeIndex].puts += asset.balance;
    }

    // return the index of the strike which was just modified
    return addedStrikeIndex;
  }

  ////////////////////////
  //      Modifiers     //
  ////////////////////////

  modifier onlyAccounts() {
    if (msg.sender != address(accounts)) revert PM_NotAccounts();
    _;
  }
}
