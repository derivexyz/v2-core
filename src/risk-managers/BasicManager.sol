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

  uint immutable startingHour;

  uint constant MAX_STRIKES = 64;

  /// @dev Pricing module to get option mark-to-market price
  IOptionPricing public pricing;

  /// @dev Perp Margin Requirements: maintenance and initial margin requirements
  PerpMarginRequirements public perpMarginRequirements;

  /// @dev Option Margin Parameters. See getIsolatedMargin for how it is used in the formula
  OptionMarginParameters public optionMarginParams;

  /// @dev if an IAsset address is whitelisted.
  mapping(IAsset => AssetDetail) public assetDetails;

  mapping(uint => ISpotFeed) public spotFeeds;
  mapping(uint => ISettlementFeed) public settlementFeeds;
  mapping(uint => IFutureFeed) public futureFeeds;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(IAccounts accounts_, ICashAsset cashAsset_) BaseManager(accounts_, cashAsset_) {
    startingHour = block.timestamp / 1 hours;
  }

  ////////////////////////
  //    Admin-Only     //
  ///////////////////////

  function whitelistAsset(IAsset _asset, uint8 _marketId, AssetType _type) external onlyOwner {
    // registered asset
    assetDetails[_asset] = AssetDetail({isWhitelisted: true, marketId: _marketId, assetType: _type});
  }

  function setOraclesForMarket(
    uint8 marketId,
    ISpotFeed spotFeed,
    ISettlementFeed settlementFeed,
    IFutureFeed futureFeed
  ) external onlyOwner {
    // registered asset
    spotFeeds[marketId] = spotFeed;
    settlementFeeds[marketId] = settlementFeed;
    futureFeeds[marketId] = futureFeed;
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
    // todo: update to per-market, use for mark to market price
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
      // allow cash
      if (address(assetDeltas[i].asset) == address(cashAsset)) continue;

      AssetDetail memory detail = assetDetails[assetDeltas[i].asset];

      if (!detail.isWhitelisted) revert PM_UnsupportedAsset();

      if (detail.assetType == AssetType.Perpetual) {
        // settle perps if the user has perp position
        _settleAccountPerps(IPerpAsset(address(assetDeltas[i].asset)), accountId);
      }
    }

    int cashBalance = accounts.getBalance(accountId, cashAsset, 0);

    // todo: don't allow borrowing cash

    int margin = _getMargin(accountId);

    // cash deposited has to cover net option margin + net perp margin
    if (cashBalance + margin < 0) {
      revert PM_PortfolioBelowMargin(accountId, -(margin));
    }
  }

  /**
   * @notice get the net margin for the option positions. This is expected to be negative
   * @param accountId Account Id for which to check
   */
  function _getMargin(uint accountId) internal view returns (int margin) {
    // get portfolio from array of balances
    IAccounts.AssetBalance[] memory assetBalances = accounts.getAccountBalances(accountId);
    BasicManagerPortfolio memory portfolio = _arrangePortfolio(assetBalances);

    // for each subAccount, get margin and sum it up
    for (uint i = 0; i < portfolio.subAccounts.length; i++) {
      margin += _getSubAccountMargin(portfolio.subAccounts[i]);
    }
  }

  function _getSubAccountMargin(BasicManagerSubAccount memory subAccount) internal view returns (int) {
    int indexPrice = spotFeeds[subAccount.marketId].getSpot().toInt256();

    int netPerpMargin = _getNetPerpMargin(subAccount, indexPrice);
    int netOptionMargin = _getNetOptionMargin(subAccount);
    return netPerpMargin + netOptionMargin;
  }

  /**
   * @notice get the margin required for the perp position of an subAccount
   * @return net margin for a perp position, always negative
   */
  function _getNetPerpMargin(BasicManagerSubAccount memory subAccount, int indexPrice) internal view returns (int) {
    uint notional = subAccount.perpPosition.multiplyDecimal(indexPrice).abs();
    int marginRequired = notional.multiplyDecimal(perpMarginRequirements.imRequirement).toInt256();
    return -marginRequired;
  }

  /**
   * @notice get the net margin for the option positions. This is expected to be negative
   */
  function _getNetOptionMargin(BasicManagerSubAccount memory subAccount) internal view returns (int margin) {
    // for each expiry, sum up the margin requirement
    for (uint i = 0; i < subAccount.expiryHoldings.length; i++) {
      margin += _calcNetBasicMarginSingleExpiry(subAccount.marketId, subAccount.option, subAccount.expiryHoldings[i]);
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
      for (uint8 id; id < 256; id++) {
        if (marketBitMap & (1 << id) != 0) {
          marketId = id;
          // mark this market id as used => flip it back to 0 with xor
          marketBitMap ^= (1 << id);
          break;
        }
      }
      portfolio.subAccounts[i].marketId = marketId;

      // 2. filter through all balances and only find perp or option for this market

      // temporary holding array,
      ExpiryHolding[] memory tempHoldings = new ExpiryHolding[](assets.length);
      uint numExpires;
      uint expiryProducts = 1; // the product of all expiry - start block hour

      for (uint j; j < assets.length; j++) {
        IAccounts.AssetBalance memory currentAsset = assets[j];
        if (currentAsset.asset == cashAsset) continue;

        AssetDetail memory detail = assetDetails[currentAsset.asset];
        if (detail.marketId != marketId) continue;

        // if it's perp asset, update the perp position directly
        if (detail.assetType == AssetType.Perpetual) {
          BasicManagerPortfolioLib.addPerpToPortfolio(
            portfolio.subAccounts[i], currentAsset.asset, currentAsset.balance
          );
        } else if (detail.assetType == AssetType.Option) {
          portfolio.subAccounts[i].option = IOption(address(currentAsset.asset));
          (uint expiry, uint strike, bool isCall) = OptionEncoding.fromSubId(uint96(currentAsset.subId));
          uint expiryInHoursSinceStart = (expiry / 1 hours) - startingHour;
          if (expiryProducts % expiryInHoursSinceStart != 0) {
            // new expiry!
            tempHoldings[numExpires].expiry = expiry;
            tempHoldings[numExpires].strikes = new ISingleExpiryPortfolio.Strike[](32);

            numExpires++;
            expiryProducts *= expiryInHoursSinceStart;
          }

          // add strike to counter
          // find the counter
          for (uint k; k < numExpires; k++) {
            if (tempHoldings[k].expiry == expiry) {
              // find and add strike in expiry holding
              BasicManagerPortfolioLib.addOptionToExpiry(tempHoldings[k], strike, isCall, currentAsset.balance);
              break;
            }
          }
        }
      }

      // initiate expiry holdings for each subAccount
      portfolio.subAccounts[i].expiryHoldings = new ExpiryHolding[](numExpires);

      // initiate expiry holdings
      for (uint j; j < numExpires; j++) {
        portfolio.subAccounts[i].expiryHoldings[j].strikes = new ISingleExpiryPortfolio.Strike[](
          tempHoldings[j].numStrikesHeld
        );

        // copy value over
        portfolio.subAccounts[i].expiryHoldings[j].expiry = tempHoldings[j].expiry;
        portfolio.subAccounts[i].expiryHoldings[j].numStrikesHeld = tempHoldings[j].numStrikesHeld;
        for (uint k; k < tempHoldings[j].numStrikesHeld; k++) {
          portfolio.subAccounts[i].expiryHoldings[j].strikes[k] = tempHoldings[j].strikes[k];
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
  function _calcNetBasicMarginSingleExpiry(uint marketId, IOption option, ExpiryHolding memory expiryHolding)
    internal
    view
    returns (int margin)
  {
    // calculate total net calls. If net call > 0, then max loss is bounded when spot goes to infinity
    int netCalls;
    for (uint i; i < expiryHolding.numStrikesHeld; i++) {
      netCalls += expiryHolding.strikes[i].calls;
    }
    bool lossBounded = netCalls >= 0;

    int maxLossMargin = 0;
    int isolatedMargin = 0;
    bool zeroStrikeOwnable2Step;

    IFutureFeed feed = futureFeeds[marketId];

    for (uint i; i < expiryHolding.numStrikesHeld; i++) {
      int forwardPrice = feed.getFuturePrice(expiryHolding.expiry).toInt256();

      // only calculate the max loss margin if loss is bounded (net calls > 0)
      if (lossBounded) {
        uint scenarioPrice = expiryHolding.strikes[i].strike;
        maxLossMargin = SignedMath.min(_calcPayoffAtPrice(option, expiryHolding, scenarioPrice), maxLossMargin);
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
    if (!assetDetails[option].isWhitelisted) revert PM_UnsupportedAsset();
    _settleAccountOptions(option, accountId);
  }

  ////////////////////////
  //   View Functions   //
  ////////////////////////

  /**
   * @dev return the margin for an account, it means the account is insolvent
   */
  function getMargin(uint accountId) external view returns (int) {
    return _getMargin(accountId);
  }

  function getIsolatedMargin(uint8 marketId, uint strike, uint expiry, int calls, int puts, bool isMaintenance)
    external
    view
    returns (int)
  {
    int forwardPrice = futureFeeds[marketId].getFuturePrice(expiry).toInt256();
    return _getIsolatedMargin(strike, calls, puts, forwardPrice, isMaintenance);
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

    // if marketId 1 is tracked, trackedMarketBitMap = 0000..00010
    // if marketId 2 is tracked, trackedMarketBitMap = 0000..00100

    // count how many unique markets there are
    for (uint i; i < userBalances.length; ++i) {
      currentAsset = userBalances[i];
      if (address(currentAsset.asset) == address(cashAsset)) {
        cashBalance = currentAsset.balance;
        continue;
      }

      // else, it must be perp or option for one of the registered assets
      AssetDetail memory detail = assetDetails[userBalances[i].asset];
      uint marketBit = 1 << detail.marketId;
      if (trackedMarketBitMap & marketBit == 0) {
        marketCount++;
        trackedMarketBitMap |= (1 << detail.marketId);
      }
    }
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
  function _calcPayoffAtPrice(IOption option, ExpiryHolding memory expiryHolding, uint price)
    internal
    pure
    returns (int payoff)
  {
    for (uint i; i < expiryHolding.numStrikesHeld; i++) {
      ISingleExpiryPortfolio.Strike memory currentStrike = expiryHolding.strikes[i];
      payoff += option.getSettlementValue(currentStrike.strike, currentStrike.calls, price, true);
      payoff += option.getSettlementValue(currentStrike.strike, currentStrike.puts, price, false);
    }
  }

  ////////////////////////
  //      Modifiers     //
  ////////////////////////

  modifier onlyAccounts() {
    if (msg.sender != address(accounts)) revert PM_NotAccounts();
    _;
  }
}
