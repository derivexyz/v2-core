// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/math/SignedMath.sol";

import "lyra-utils/decimals/DecimalMath.sol";
import "lyra-utils/decimals/SignedDecimalMath.sol";
import "lyra-utils/math/IntLib.sol";
import "lyra-utils/ownership/Owned.sol";

import "src/interfaces/IManager.sol";
import "src/interfaces/IAccounts.sol";
import "src/interfaces/ICashAsset.sol";
import "src/interfaces/IPerpAsset.sol";
import "src/interfaces/IBaseManager.sol";
import "src/interfaces/IOption.sol";
import "src/interfaces/IOptionPricing.sol";
import "src/interfaces/IChainlinkSpotFeed.sol";
import "src/interfaces/ISimpleManager.sol";

import "./BaseManager.sol";

import "forge-std/console2.sol";

/**
 * @title SimpleManager
 * @author Lyra
 * @notice Risk Manager that margin in perp, cash and option in isolation.
 */

contract SimpleManager is ISimpleManager, BaseManager {
  using SignedDecimalMath for int;
  using DecimalMath for uint;
  using SafeCast for uint;
  using IntLib for int;

  ///////////////
  // Variables //
  ///////////////

  uint constant MAX_STRIKES = 64;

  /// @dev Perp asset address
  IPerpAsset public immutable perp;

  /// @dev Future feed oracle to get future price for an expiry
  IChainlinkSpotFeed public immutable feed;

  /// @dev Pricing module to get option mark-to-market price
  IOptionPricing public pricing;

  /// @dev Perp Maintenance margin requirement: min percentage of notional value to avoid liquidation
  uint public perpMMRequirement = 0.03e18;

  /// @dev Perp Initial margin requirement: min percentage of notional value to modify a position
  uint public perpIMRequirement = 0.05e18;

  /// @dev Option Maintenance margin requirement: min percentage of spot + mark to market
  int public optionStaticMMRequirement = 0.075e18;

  /// @dev todo: add descriptions
  int public baselineOptionIM = 0.2e18;

  /// @dev todo: add descriptions
  int public baselineOptionMM = 0.1e18;

  /// @dev todo: add descriptions
  int public minStaticMMMargin = 0.125e18;

  int public minStaticIMMargin = 0.08e18;

  // int public minPutMarginInStrike = 0.5e18;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(IAccounts accounts_, ICashAsset cashAsset_, IOption option_, IPerpAsset perp_, IChainlinkSpotFeed feed_)
    BaseManager(accounts_, feed_, feed_, cashAsset_, option_)
  {
    perp = perp_;
    feed = feed_;
  }

  ////////////////////////
  //    Admin-Only     //
  ///////////////////////

  /**
   * @notice Set the maintenance margin requirement
   * @param _mmRequirement new maintenance margin requirement
   * @param _imRequirement new initial margin requirement
   */
  function setPerpMarginRequirements(uint _mmRequirement, uint _imRequirement) external onlyOwner {
    if (_mmRequirement > _imRequirement) revert PM_InvalidMarginRequirement();
    if (_mmRequirement == 0 || _mmRequirement >= 1e18) revert PM_InvalidMarginRequirement();
    if (_imRequirement >= 1e18) revert PM_InvalidMarginRequirement();

    perpMMRequirement = _mmRequirement;
    perpIMRequirement = _imRequirement;

    emit MarginRequirementsSet(_mmRequirement, _imRequirement);
  }

  /**
   * @notice Set the pricing module
   * @param _pricing new pricing module
   */
  function setPricingModule(IOptionPricing _pricing) external onlyOwner {
    pricing = IOptionPricing(_pricing);
  }

  ////////////////////////
  //   Account Hooks   //
  ////////////////////////

  /**
   * @notice Ensures asset is valid and Max Loss margin is met.
   * @param accountId Account for which to check trade.
   */
  function handleAdjustment(uint accountId, uint, /*tradeId*/ address, AssetDelta[] calldata assetDeltas, bytes memory)
    public
    view
    override
  {
    // check the call is from Accounts

    // check assets are only cash and perp
    for (uint i = 0; i < assetDeltas.length; i++) {
      if (assetDeltas[i].asset != cashAsset && assetDeltas[i].asset != perp && assetDeltas[i].asset != option) {
        revert PM_UnsupportedAsset();
      }
    }

    int indexPrice = feed.getSpot().toInt256();

    int cashBalance = accounts.getBalance(accountId, cashAsset, 0);

    // todo: don't allow borrowing cash

    int perpMargin = _getPerpMargin(accountId, indexPrice);

    int optionMargin = _getOptionMargin(accountId, indexPrice);

    if (cashBalance < perpMargin + optionMargin) {
      revert PM_PortfolioBelowMargin(accountId, perpMargin);
    }
  }

  /**
   * @notice get the margin required for the perp position
   * @param accountId Account Id for which to check
   */
  function _getPerpMargin(uint accountId, int indexPrice) internal view returns (int) {
    uint notional = accounts.getBalance(accountId, perp, 0).multiplyDecimal(indexPrice).abs();
    int marginRequired = notional.multiplyDecimal(perpIMRequirement).toInt256();
    return marginRequired;
  }

  /**
   * @notice get the margin required for the option positions
   * @param accountId Account Id for which to check
   */
  function _getOptionMargin(uint accountId, int indexPrice) internal view returns (int margin) {
    // compute net call

    IBaseManager.Portfolio memory portfolio = _arrangePortfolio(accounts.getAccountBalances(accountId));

    margin = _calcSimpleMargin(portfolio, indexPrice);
  }

  /**
   * @notice Ensures new manager is valid.
   * @param newManager IManager to change account to.
   */
  function handleManagerChange(uint, /*accountId*/ IManager newManager) external view {
    if (!whitelistedManager[address(newManager)]) {
      revert PM_NotWhitelistManager();
    }
  }

  /**
   * @notice to settle an account, clear PNL and funding in the perp contract and pay out cash
   */
  function settlePerps(uint accountId) external {
    perp.updateFundingRate();
    perp.applyFundingOnAccount(accountId);

    // settle perp
    int netCash = perp.settleRealizedPNLAndFunding(accountId);

    cashAsset.updateSettledCash(netCash);

    // update user cash amount
    accounts.managerAdjustment(AccountStructs.AssetAdjustment(accountId, cashAsset, 0, netCash, bytes32(0)));

    emit AccountSettled(accountId, netCash);
  }

  /**
   * @notice Arrange portfolio into cash + arranged
   *         array of [strikes][calls / puts].
   *         Unlike PCRM, the forwards are purposefully not filtered.
   * @param assets Array of balances for given asset and subId.
   * @return portfolio Cash + option holdings.
   */
  function _arrangePortfolio(AccountStructs.AssetBalance[] memory assets)
    internal
    view
    returns (IBaseManager.Portfolio memory portfolio)
  {
    // note: differs from PCRM._arrangePortfolio since forwards aren't filtered
    // todo: [Josh] can just combine with PCRM _arrangePortfolio and remove struct
    portfolio.strikes = new IBaseManager.Strike[](
      MAX_STRIKES > assets.length ? assets.length : MAX_STRIKES
    );

    AccountStructs.AssetBalance memory currentAsset;
    for (uint i; i < assets.length; ++i) {
      currentAsset = assets[i];
      if (address(currentAsset.asset) == address(option)) {
        _addOption(portfolio, currentAsset);
      } else if (address(currentAsset.asset) == address(cashAsset)) {
        if (currentAsset.balance < 0) revert("Negative Cash");

        portfolio.cash = currentAsset.balance;
      } else if (currentAsset.asset == perp) {
        portfolio.perp = currentAsset.balance;
      } else {
        revert("WHAT");
      }
    }
  }

  /**
   * @notice Calculate the required margin of the account.
   *      If the account's option require 10K cash, this function will return -10K
   *
   * @dev If an account's max loss is bounded, return min (max loss margin, isolated margin)
   *      If an account's max loss is unbounded, return isolated margin
   * @param portfolio Account portfolio.
   * @return margin If the account's option require 10K cash, this function will return -10K
   */
  function _calcSimpleMargin(IBaseManager.Portfolio memory portfolio, int indexPrice)
    internal
    view
    returns (int margin)
  {
    // calculate total net calls. If net call > 0, then max loss is bounded when spot goes to infinity
    int netCalls;
    for (uint i; i < portfolio.numStrikesHeld; i++) {
      netCalls += portfolio.strikes[i].calls;
    }
    bool lossBounded = netCalls > 0;

    int maxLossMargin = 0;
    int isolatedMargin = 0;
    bool zeroStrikeOwned;

    for (uint i; i < portfolio.numStrikesHeld; i++) {
      // only calculate the max loss margin if loss is bounded (net calls > 0)
      if (lossBounded) {
        uint scenarioPrice = portfolio.strikes[i].strike;
        maxLossMargin = SignedMath.min(_calcPayoffAtPrice(portfolio, scenarioPrice), maxLossMargin);
        if (scenarioPrice == 0) {
          zeroStrikeOwned = true;
        }
      }

      // calculate isolated margin for this strike, aggregate to isolatedMargin
      isolatedMargin += _getIsolatedMargin(
        portfolio.strikes[i].strike,
        portfolio.expiry,
        portfolio.strikes[i].calls,
        portfolio.strikes[i].puts,
        indexPrice,
        false // is maintenance = false
      );
    }

    // Ensure $0 scenario is always evaluated.
    if (lossBounded && !zeroStrikeOwned) {
      maxLossMargin = SignedMath.min(_calcPayoffAtPrice(portfolio, 0), maxLossMargin);
    }

    return SignedMath.min(isolatedMargin, maxLossMargin);
  }

  function getIsolatedMargin(uint strike, uint expiry, int calls, int puts, bool isMaintenance)
    external
    view
    returns (int)
  {
    int indexPrice = feed.getSpot().toInt256();
    return _getIsolatedMargin(strike, expiry, calls, puts, indexPrice, isMaintenance);
  }

  function _getIsolatedMargin(uint strike, uint expiry, int calls, int puts, int indexPrice, bool isMaintenance)
    internal
    view
    returns (int margin)
  {
    if (calls < 0) {
      margin += _getIsolatedMarginForCall(strike, expiry, calls, indexPrice, isMaintenance);
    }
    if (puts < 0) {
      margin += _getIsolatedMarginForPut(strike, expiry, puts, indexPrice, isMaintenance);
    }
  }

  /**
   * @dev calculate isolated margin requirement for a put option
   * @dev expected to return a negative number
   */
  function _getIsolatedMarginForPut(uint strike, uint expiry, int amount, int index, bool isMaintenance)
    internal
    view
    returns (int)
  {
    int baseLine = isMaintenance ? baselineOptionMM : baselineOptionIM;
    int minStaticMargin = isMaintenance ? minStaticMMMargin : minStaticIMMargin;

    // this ratio become negative if option is ITM
    int otmRatio = (index - strike.toInt256()).divideDecimal(index);

    int extraMargin = SignedMath.min(SignedMath.max(baseLine - otmRatio, minStaticMargin).multiplyDecimal(index), 0)
      // strike.toInt256().multiplyDecimal(minPutMarginInStrike)
      .multiplyDecimal(amount);

    // int mtm = pricing.getMTM(strike, expiry, true).toInt256().multiplyDecimal(amount);

    return extraMargin;
  }

  /**
   * @dev calculate isolated margin requirement for a call option
   * @param amount expected a negative number, representing amount of shorts
   */
  function _getIsolatedMarginForCall(uint strike, uint expiry, int amount, int index, bool isMaintenance)
    internal
    view
    returns (int)
  {
    int baseLine = isMaintenance ? baselineOptionMM : baselineOptionIM;
    int minStaticMargin = isMaintenance ? minStaticMMMargin : minStaticIMMargin;

    // this ratio become negative if option is ITM
    int otmRatio = (strike.toInt256() - index).divideDecimal(index);

    int extraMargin =
      SignedMath.max(baseLine - otmRatio, minStaticMargin).multiplyDecimal(index).multiplyDecimal(amount);

    console2.log("extraMargin", extraMargin);

    // int mtm = pricing.getMTM(strike, expiry, true).toInt256().multiplyDecimal(amount);

    return extraMargin;
  }

  /**
   * @notice Calculate the full portfolio payoff at a given settlement price.
   *         This is used in '_calcMaxLossMargin()' calculated the max loss of a given portfolio.
   * @param portfolio Account portfolio.
   * @param price Assumed scenario price.
   * @return payoff Net $ profit or loss of the portfolio given a settlement price.
   */
  function _calcPayoffAtPrice(IBaseManager.Portfolio memory portfolio, uint price) internal view returns (int payoff) {
    for (uint i; i < portfolio.numStrikesHeld; i++) {
      IBaseManager.Strike memory currentStrike = portfolio.strikes[i];
      payoff += option.getSettlementValue(currentStrike.strike, currentStrike.calls, price, true);
      payoff += option.getSettlementValue(currentStrike.strike, currentStrike.puts, price, false);
    }
  }

  //////////
  // View //
  //////////
}
