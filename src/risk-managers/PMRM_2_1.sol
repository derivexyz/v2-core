// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/math/Math.sol";
import "openzeppelin/utils/math/SignedMath.sol";
import "openzeppelin/security/ReentrancyGuard.sol";

import "lyra-utils/encoding/OptionEncoding.sol";
import "lyra-utils/decimals/DecimalMath.sol";
import "lyra-utils/decimals/SignedDecimalMath.sol";

import {IManager} from "../interfaces/IManager.sol";
import {ISubAccounts} from "../interfaces/ISubAccounts.sol";
import {ICashAsset} from "../interfaces/ICashAsset.sol";
import {IPerpAsset} from "../interfaces/IPerpAsset.sol";
import {IPMRMLib_2_1} from "../interfaces/IPMRMLib_2_1.sol";
import {IOptionAsset} from "../interfaces/IOptionAsset.sol";
import {ISpotFeed} from "../interfaces/ISpotFeed.sol";
import {ILiquidatableManager} from "../interfaces/ILiquidatableManager.sol";
import {IVolFeed} from "../interfaces/IVolFeed.sol";
import {IInterestRateFeed} from "../interfaces/IInterestRateFeed.sol";
import {IPMRM_2_1} from "../interfaces/IPMRM_2_1.sol";
import {IWrappedERC20Asset} from "../interfaces/IWrappedERC20Asset.sol";
import {IDutchAuction} from "../interfaces/IDutchAuction.sol";
import {IForwardFeed} from "../interfaces/IForwardFeed.sol";
import {IBasePortfolioViewer} from "../interfaces/IBasePortfolioViewer.sol";

import {BaseManager} from "./BaseManager.sol";

/**
 * @title PMRM
 * @author Lyra
 * @notice Risk Manager that uses a SPAN like methodology to margin an options portfolio.
 */
contract PMRM_2_1 is IPMRM_2_1, ILiquidatableManager, BaseManager, ReentrancyGuard {
  using SignedDecimalMath for int;
  using DecimalMath for uint;
  using SafeCast for uint;
  using SafeCast for int;

  IOptionAsset public immutable option;
  IPerpAsset public immutable perp;

  /////////////////
  //  Variables  //
  /////////////////

  ISpotFeed public spotFeed;
  IInterestRateFeed public interestRateFeed;
  IVolFeed public volFeed;
  ISpotFeed public stableFeed;
  IForwardFeed public forwardFeed;

  /// @dev lib contract
  IPMRMLib_2_1 public immutable lib;

  /// @dev Value to help optimise the arranging of portfolio. Should be minimised if possible.
  uint public maxExpiries = 11;

  IPMRM_2_1.Scenario[] internal marginScenarios;

  mapping(address => ISpotFeed) public collateralSpotFeeds;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(
    ISubAccounts subAccounts_,
    ICashAsset cashAsset_,
    IOptionAsset option_,
    IPerpAsset perp_,
    IDutchAuction liquidation_,
    Feeds memory feeds_,
    IBasePortfolioViewer viewer_,
    IPMRMLib_2_1 lib_
  ) BaseManager(subAccounts_, cashAsset_, liquidation_, viewer_) {
    spotFeed = feeds_.spotFeed;
    stableFeed = feeds_.stableFeed;
    forwardFeed = feeds_.forwardFeed;
    interestRateFeed = feeds_.interestRateFeed;
    volFeed = feeds_.volFeed;
    lib = lib_;

    option = option_;
    perp = perp_;
  }

  /////////////////////
  //   Owner-only    //
  /////////////////////

  /**
   * @dev set max tradeable expiries in a single account
   */
  function setMaxExpiries(uint _maxExpiries) external onlyOwner {
    if (_maxExpiries <= maxExpiries || _maxExpiries > 30) {
      revert PMRM_InvalidMaxExpiries();
    }
    maxExpiries = _maxExpiries;
    emit MaxExpiriesUpdated(_maxExpiries);
  }

  function setInterestRateFeed(IInterestRateFeed _interestRateFeed) external onlyOwner {
    interestRateFeed = _interestRateFeed;
    emit InterestRateFeedUpdated(_interestRateFeed);
  }

  function setVolFeed(IVolFeed _volFeed) external onlyOwner {
    volFeed = _volFeed;
    emit VolFeedUpdated(_volFeed);
  }

  function setSpotFeed(ISpotFeed _spotFeed) external onlyOwner {
    spotFeed = _spotFeed;
    emit SpotFeedUpdated(_spotFeed);
  }

  function setStableFeed(ISpotFeed _stableFeed) external onlyOwner {
    stableFeed = _stableFeed;
    emit StableFeedUpdated(_stableFeed);
  }

  function setForwardFeed(IForwardFeed _forwardFeed) external onlyOwner {
    forwardFeed = _forwardFeed;
    emit ForwardFeedUpdated(_forwardFeed);
  }
  
  function setCollateralSpotFeed(address asset, ISpotFeed _feed) external onlyOwner {
    // TODO: make sure collateral assets are not the option/cash/perp assets
    collateralSpotFeeds[asset] = _feed;
  }

  /**
   * @notice Sets the scenarios for managing margin positions.
   * @dev Only the contract owner can invoke this function.
   * @param _scenarios An array of Scenario structs representing the margin scenarios.
   *                   Each Scenario struct contains relevant data for a specific scenario.
   */
  function setScenarios(IPMRM_2_1.Scenario[] memory _scenarios) external onlyOwner {
    if (_scenarios.length == 0 || _scenarios.length > 40) {
      revert PMRM_InvalidScenarios();
    }
    for (uint i = 0; i < _scenarios.length; i++) {
      // TODO: check that abs/linear vol shocks have 0 spotShock. only one of each too
      if (marginScenarios.length <= i) {
        marginScenarios.push(_scenarios[i]);
      } else {
        marginScenarios[i] = _scenarios[i];
      }
    }

    uint marginScenariosLength = marginScenarios.length;
    for (uint i = _scenarios.length; i < marginScenariosLength; i++) {
      marginScenarios.pop();
    }
    emit ScenariosUpdated(_scenarios);
  }

  ///////////////////////
  //   Account Hooks   //
  ///////////////////////

  /**
   * @notice Handles adjustments to the margin positions for a given account.
   * @dev Only the accounts contract can invoke this function.
   * @param accountId The ID of the account.
   * @param tradeId The ID of the trade.
   * @param caller The address of the caller.
   * @param assetDeltas An array of AssetDelta structs representing changes to account assets.
   * @param managerData Additional data (unused in this function).
   */
  function handleAdjustment(
    uint accountId,
    uint tradeId,
    address caller,
    ISubAccounts.AssetDelta[] memory assetDeltas,
    bytes calldata managerData
  ) external onlyAccounts nonReentrant {
    _preAdjustmentHooks(accountId, tradeId, caller, assetDeltas, managerData);

    // Block any transfers where an account is under liquidation
    _checkIfLiveAuction(accountId);

    bool riskAdding = false;
    for (uint i = 0; i < assetDeltas.length; i++) {
      if (assetDeltas[i].asset == perp) {
        // Settle perp PNL into cash if the user traded perp in this tx.
        _settlePerpRealizedPNL(perp, accountId);
        riskAdding = true;
      } else if (
        assetDeltas[i].asset != cashAsset  //
        && assetDeltas[i].asset != option  //
        && address(collateralSpotFeeds[address(assetDeltas[i].asset)]) == address(0)
      ) {
        revert PMRM_UnsupportedAsset();
      } else {
        if (assetDeltas[i].delta < 0) {
          riskAdding = true;
        }
      }
    }

    ISubAccounts.AssetBalance[] memory assetBalances = subAccounts.getAccountBalances(accountId);

    if (
      assetBalances.length > maxAccountSize //
        && viewer.getPreviousAssetsLength(assetBalances, assetDeltas) < assetBalances.length
    ) {
      revert PMRM_TooManyAssets();
    }

    if (!riskAdding) {
      // Early exit if only adding cash/option/baseAsset
      return;
    }
    _assessRisk(caller, accountId, assetBalances);
  }

  ///////////////////////
  // Arrange Portfolio //
  ///////////////////////

  function _assessRisk(address caller, uint accountId, ISubAccounts.AssetBalance[] memory assetBalances) internal view {
    IPMRM_2_1.Portfolio memory portfolio = _arrangePortfolio(accountId, assetBalances);

    if (trustedRiskAssessor[caller]) {
      // If the caller is a trusted risk assessor, only use the basis contingency scenarios (3 scenarios)
      (int atmMM,,) = lib.getMarginAndMarkToMarket(portfolio, false, lib.getBasisContingencyScenarios());
      if (atmMM >= 0) return;
    } else {
      // If the caller is not a trusted risk assessor, use all the margin scenarios
      (int postIM,,) = lib.getMarginAndMarkToMarket(portfolio, true, marginScenarios);
      if (postIM >= 0) return;
    }
    revert PMRM_InsufficientMargin();
  }

  /**
   * @notice Arrange portfolio into cash + arranged
   *         array of [strikes][calls / puts / forwards].
   * @param assets Array of balances for given asset and subId.
   * @return portfolio Cash + option holdings.
   */
  function _arrangePortfolio(uint accountId, ISubAccounts.AssetBalance[] memory assets)
    internal
    view
    returns (IPMRM_2_1.Portfolio memory portfolio)
  {
    (uint seenExpiries, uint collateralCount, PortfolioExpiryData[] memory expiryCount) = _countExpiriesAndOptions(assets);

    portfolio.expiries = new ExpiryHoldings[](seenExpiries);
    (portfolio.spotPrice, portfolio.minConfidence) = spotFeed.getSpot();
    (uint stablePrice,) = stableFeed.getSpot();
    portfolio.stablePrice = stablePrice;

    _initialiseExpiries(portfolio, expiryCount);
    _arrangeOptions(accountId, portfolio, assets, collateralCount, expiryCount);

    if (portfolio.perpPosition != 0) {
      (uint perpPrice, uint perpConfidence) = perp.getPerpPrice();
      portfolio.perpPrice = perpPrice;
      portfolio.minConfidence = Math.min(portfolio.minConfidence, perpConfidence);
    }

    portfolio = lib.addPrecomputes(portfolio);

    return portfolio;
  }

  function _countExpiriesAndOptions(ISubAccounts.AssetBalance[] memory assets)
    internal
    view
    returns (uint seenExpiries, uint collateralCount, IPMRM_2_1.PortfolioExpiryData[] memory expiryCount)
  {
    uint assetLen = assets.length;

    collateralCount = 0;
    seenExpiries = 0;
    expiryCount = new IPMRM_2_1.PortfolioExpiryData[](maxExpiries > assetLen ? assetLen : maxExpiries);

    // Just count the number of options per expiry
    for (uint i = 0; i < assetLen; ++i) {
      ISubAccounts.AssetBalance memory currentAsset = assets[i];
      if (address(currentAsset.asset) == address(option)) {
        (uint optionExpiry,,) = OptionEncoding.fromSubId(currentAsset.subId.toUint96());

        bool found = false;
        for (uint j = 0; j < seenExpiries; j++) {
          if (expiryCount[j].expiry == optionExpiry) {
            expiryCount[j].optionCount++;
            found = true;
            break;
          }
        }
        if (!found) {
          if (seenExpiries == maxExpiries) {
            revert PMRM_TooManyExpiries();
          }
          expiryCount[seenExpiries++] = PortfolioExpiryData({expiry: uint64(optionExpiry), optionCount: 1});
        }
      } else if (address(collateralSpotFeeds[address(currentAsset.asset)]) != address(0)) {
        collateralCount++;
      }
    }

    return (seenExpiries, collateralCount, expiryCount);
  }

  /**
   * @dev initial array of empty ExpiryHolding structs in the portfolio struct
   */
  function _initialiseExpiries(IPMRM_2_1.Portfolio memory portfolio, PortfolioExpiryData[] memory expiryCount)
    internal
    view
  {
    for (uint i = 0; i < portfolio.expiries.length; ++i) {
      (uint forwardFixedPortion, uint forwardVariablePortion, uint fwdConfidence) =
        forwardFeed.getForwardPricePortions(expiryCount[i].expiry);
      (int rate, uint rateConfidence) = interestRateFeed.getInterestRate(expiryCount[i].expiry);
      // We dont compare this to the portfolio.minConfidence yet - we do that in preComputes
      uint minConfidence = Math.min(fwdConfidence, rateConfidence);

      // if an option expired, also set secToExpiry to 0
      uint64 secToExpiry =
        expiryCount[i].expiry > uint64(block.timestamp) ? uint64(expiryCount[i].expiry - block.timestamp) : 0;
      portfolio.expiries[i] = ExpiryHoldings({
        expiry: expiryCount[i].expiry,
        secToExpiry: secToExpiry,
        options: new StrikeHolding[](expiryCount[i].optionCount),
        forwardFixedPortion: forwardFixedPortion,
        forwardVariablePortion: forwardVariablePortion,
        // We assume the rate is always positive. TODO: this should be checked
        rate: SignedMath.max(0, rate).toUint256(),
        minConfidence: minConfidence,
        netOptions: 0,
        // vol shocks are added in addPrecomputes
        mtm: 0,
        basisScenarioUpMtM: 0,
        basisScenarioDownMtM: 0,
        volShockUp: 0,
        volShockDown: 0,
        staticDiscount: 0
      });
    }
  }

  function _arrangeOptions(
    uint accountId,
    IPMRM_2_1.Portfolio memory portfolio,
    ISubAccounts.AssetBalance[] memory assets,
    uint collateralCount,
    PortfolioExpiryData[] memory expiryCount
  ) internal view {
    for (uint i = 0; i < assets.length; ++i) {
      ISubAccounts.AssetBalance memory currentAsset = assets[i];
      if (address(currentAsset.asset) == address(option)) {
        (uint optionExpiry, uint strike, bool isCall) = OptionEncoding.fromSubId(currentAsset.subId.toUint96());

        uint expiryIndex = findInArray(portfolio.expiries, optionExpiry, portfolio.expiries.length);

        ExpiryHoldings memory expiry = portfolio.expiries[expiryIndex];

        (uint vol, uint confidence) = volFeed.getVol(strike.toUint128(), optionExpiry.toUint64());

        expiry.minConfidence = Math.min(confidence, expiry.minConfidence);

        expiry.netOptions += SignedMath.abs(currentAsset.balance);

        uint index = --expiryCount[expiryIndex].optionCount;
        expiry.options[index] =
          StrikeHolding({strike: strike, vol: vol, amount: currentAsset.balance, isCall: isCall, seenInFilter: false});
      } else if (address(currentAsset.asset) == address(cashAsset)) {
        portfolio.cash = currentAsset.balance;
      } else if (address(currentAsset.asset) == address(perp)) {
        portfolio.perpPosition = currentAsset.balance;
        portfolio.perpValue = perp.getUnsettledAndUnrealizedCash(accountId);
      } else {
        (uint price, uint conf) = collateralSpotFeeds[address(currentAsset.asset)].getSpot();
        // todo safecast
        portfolio.collaterals[--collateralCount] = IPMRM_2_1.CollateralHoldings({
          asset: address(currentAsset.asset),
          value: uint(currentAsset.balance) * price / portfolio.stablePrice,
          minConfidence: Math.min(conf, portfolio.minConfidence)
        });
      }
      // No need to catch other assets, as they will be caught in handleAdjustment.
      // They will also revert in the "else" when trying to fetch non existent spot feed
    }
  }

  /**
   * @dev Return index of expiry in the array, revert if not found
   */
  function findInArray(ExpiryHoldings[] memory expiryData, uint expiryToFind, uint arrayLen)
    internal
    pure
    returns (uint index)
  {
    unchecked {
      for (uint i; i < arrayLen; ++i) {
        if (expiryData[i].expiry == expiryToFind) {
          return i;
        }
      }
      revert PMRM_FindInArrayError();
    }
  }

  /**
   * @dev Iterate through all asset delta, charge OI fee for perp and option assets
   */
  function _chargeAllOIFee(address caller, uint accountId, uint tradeId, ISubAccounts.AssetDelta[] memory assetDeltas)
    internal
    override
  {
    if (feeBypassedCaller[caller]) return;

    uint fee;
    // iterate through all asset changes, if it's option asset, change if OI increased
    for (uint i; i < assetDeltas.length; i++) {
      if (address(assetDeltas[i].asset) == address(option)) {
        fee += _getOptionOIFee(option, forwardFeed, assetDeltas[i].delta, assetDeltas[i].subId, tradeId);
      } else if (address(assetDeltas[i].asset) == address(perp)) {
        fee += _getPerpOIFee(perp, assetDeltas[i].delta, tradeId);
      }
    }

    _payFee(accountId, fee);
  }

  ////////////////
  //  External  //
  ////////////////

  /**
   * @notice Can be called by anyone to settle a perp asset in an account
   */
  function settlePerpsWithIndex(uint accountId) external {
    _settlePerpUnrealizedPNL(perp, accountId);
  }

  /**
   * @notice Can be called by anyone to settle a perp asset in an account
   */
  function settleOptions(IOptionAsset _option, uint accountId) external {
    if (_option != option) revert PMRM_UnsupportedAsset();
    _settleAccountOptions(_option, accountId);
  }

  ////////////
  //  View  //
  ////////////

  /**
   * @notice Return all scenarios
   */
  function getScenarios() external view returns (IPMRM_2_1.Scenario[] memory) {
    return marginScenarios;
  }

  /**
   * @notice Turn balance into an arranged portfolio struct
   */
  function arrangePortfolio(uint accountId) external view returns (IPMRM_2_1.Portfolio memory portfolio) {
    return _arrangePortfolio(accountId, subAccounts.getAccountBalances(accountId));
  }

  /**
   * @notice Get the initial margin or maintenance margin of an account
   * @dev if the returned value is negative, it means the account is under margin requirement
   */
  function getMargin(uint accountId, bool isInitial) external view returns (int) {
    IPMRM_2_1.Portfolio memory portfolio = _arrangePortfolio(accountId, subAccounts.getAccountBalances(accountId));
    (int margin,,) = lib.getMarginAndMarkToMarket(portfolio, isInitial, marginScenarios);
    return margin;
  }

  /**
   * @notice Get margin level and mark to market of an account
   */
  function getMarginAndMarkToMarket(uint accountId, bool isInitial, uint scenarioId)
    external
    view
    returns (int margin, int mtm)
  {
    IPMRM_2_1.Portfolio memory portfolio = _arrangePortfolio(accountId, subAccounts.getAccountBalances(accountId));
    IPMRM_2_1.Scenario[] memory scenarios = new IPMRM_2_1.Scenario[](1);

    scenarios[0] = marginScenarios[scenarioId];

    (margin, mtm,) = lib.getMarginAndMarkToMarket(portfolio, isInitial, scenarios);
    return (margin, mtm);
  }
}
