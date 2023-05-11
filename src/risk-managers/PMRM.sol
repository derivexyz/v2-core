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
import "src/interfaces/ISpotFeed.sol";
import "src/interfaces/IBasicManager.sol";
import "src/feeds/MTMCache.sol";
import "src/interfaces/IVolFeed.sol";
import "src/interfaces/IInterestRateFeed.sol";
import "src/interfaces/IMarginAsset.sol";
import "src/interfaces/IPMRM.sol";

import "./BaseManager.sol";

import "forge-std/console2.sol";

/**
 * @title PMRM
 * @author Lyra
 * @notice Risk Manager that uses a SPAN like methodology to margin an options portfolio.
 */

contract PMRM is IPMRM, BaseManager {
  using SignedDecimalMath for int;
  using DecimalMath for uint;
  using SafeCast for uint;
  using IntLib for int;

  ///////////////
  // Constants //
  ///////////////
  uint public constant MAX_EXPIRIES = 11;

  uint public constant MAX_ASSETS = 32;

  ///////////////
  // Variables //
  ///////////////

  /// @dev Spot price oracle
  ISpotFeed public feed;
  IInterestRateFeed public interestRateFeed;
  IVolFeed public volFeed;

  IMarginAsset public immutable baseAsset;

  /// @dev Pricing module to get option mark-to-market price
  MTMCache public mtmCache;

  /// @dev Portfolio Margin Parameters: maintenance and initial margin requirements
  IPMRM.PMRMParameters public pmrmParams;
  IPMRM.VolShockParameters public volShockParams;
  IPMRM.ContingencyParameters public contingencyParams;
  IPMRM.Scenario[] public marginScenarios;

  mapping(address => bool) public trustedRiskAssessor;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(
    IAccounts accounts_,
    ICashAsset cashAsset_,
    IOption option_,
    IPerpAsset perp_,
    IForwardFeed futureFeed_,
    ISettlementFeed settlementFeed_,
    ISpotFeed spotFeed_,
    MTMCache mtmCache_,
    IInterestRateFeed interestRateFeed_,
    IVolFeed volFeed_,
    IMarginAsset baseAsset_
  ) BaseManager(accounts_, futureFeed_, settlementFeed_, cashAsset_, option_, perp_) {
    feed = spotFeed_;
    mtmCache = mtmCache_;
    interestRateFeed = interestRateFeed_;
    volFeed = volFeed_;
    baseAsset = baseAsset_;

    pmrmParams.lossFactor = 1.3e18;
    pmrmParams.epsilon = 0.05e18;
    pmrmParams.fwdStep = 0.01e18;
    pmrmParams.netPosScalar = 0.01e18;
    pmrmParams.pegLossFactor = 0.5e18;
    pmrmParams.rfrStaticDiscount = 0.95e18;
    pmrmParams.rfrMultFactor = 4e18;
    pmrmParams.rfrAdditiveFactor = 0.05e18;

    volShockParams.volRangeUp = 0.45e18;
    volShockParams.volRangeDown = 0.3e18;
    volShockParams.shortTermPower = 0.3e18;
    volShockParams.longTermPower = 0.13e18;

    contingencyParams.basePercent = 0.02e18;
    contingencyParams.perpPercent = 0.02e18;
    contingencyParams.optionPercent = 0.01e18;
    contingencyParams.fwdSpotShock1 = 0.95e18;
    contingencyParams.fwdSpotShock2 = 1.05e18;

    contingencyParams.fwdShortFactor = 0.05e18;
    contingencyParams.fwdMediumFactor = 0.125e18;
    contingencyParams.fwdLongFactor = 0.25e18;

    contingencyParams.oracleConfMargin = 0.4e18;
    contingencyParams.oracleSpotConfThreshold = 0.75e18;
    contingencyParams.oracleVolConfThreshold = 0.75e18;
    contingencyParams.oracleFutureConfThreshold = 0.75e18;
    contingencyParams.oracleDiscountConfThreshold = 0.75e18;
  }

  ////////////////////////
  //    Admin-Only     //
  ///////////////////////

  function setScenarios(IPMRM.Scenario[] memory _scenarios) external onlyOwner {
    for (uint i = 0; i < _scenarios.length; i++) {
      if (marginScenarios.length <= i) {
        marginScenarios.push(_scenarios[i]);
      } else {
        marginScenarios[i] = _scenarios[i];
      }
    }
    for (uint i = _scenarios.length; i < marginScenarios.length; i++) {
      // TODO: this probably breaks lol, should be tested
      delete marginScenarios[i];
    }
  }

  /**
   * @notice Set the maintenance margin requirement
   */
  function setPMRMParameters(IPMRM.PMRMParameters memory _pmrmParameters) external onlyOwner {
    pmrmParams = _pmrmParameters;
  }

  function setInterestRateFeed(IInterestRateFeed _interestRateFeed) external onlyOwner {
    interestRateFeed = _interestRateFeed;
  }

  function setMTMCache(MTMCache _mtmCache) external onlyOwner {
    mtmCache = _mtmCache;
  }

  function setVolFeed(IVolFeed _volFeed) external onlyOwner {
    volFeed = _volFeed;
  }

  function setVolShockParams(IPMRM.VolShockParameters memory _volShockParams) external onlyOwner {
    volShockParams = _volShockParams;
  }

  function setContingencyParams(IPMRM.ContingencyParameters memory _contingencyParams) external onlyOwner {
    contingencyParams = _contingencyParams;
  }

  function setTrustedRiskAssessor(address riskAssessor, bool trusted) external onlyOwner {
    trustedRiskAssessor[riskAssessor] = trusted;
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
    bytes memory
  ) public onlyAccounts {
    _chargeOIFee(accountId, tradeId, assetDeltas);

    // check assets are only cash and perp
    for (uint i = 0; i < assetDeltas.length; i++) {
      if (assetDeltas[i].asset == perp) {
        // settle perps if the user has perp position
        _settleAccountPerps(accountId);
      } else if (assetDeltas[i].asset != cashAsset && assetDeltas[i].asset != option) {
        revert("unsupported asset");
      }
    }

    bool isTrustedRiskAssessor = trustedRiskAssessor[caller];

    IPMRM.PMRM_Portfolio memory portfolio =
      _arrangePortfolio(accountId, accounts.getAccountBalances(accountId), !isTrustedRiskAssessor);

    _checkMargin(portfolio, marginScenarios);
  }

  ///////////////////////
  // Arrange Portfolio //
  ///////////////////////

  /**
   * @notice Arrange portfolio into cash + arranged
   *         array of [strikes][calls / puts / forwards].
   * @param assets Array of balances for given asset and subId.
   * @return portfolio Cash + option holdings.
   */
  function _arrangePortfolio(uint accountId, IAccounts.AssetBalance[] memory assets, bool addForwardCont)
    internal
    view
    returns (IPMRM.PMRM_Portfolio memory portfolio)
  {
    uint assetLen = assets.length;
    PortfolioExpiryData[] memory expiryCount =
      new PortfolioExpiryData[](MAX_EXPIRIES > assetLen ? assetLen : MAX_EXPIRIES);
    uint seenExpiries = 0;

    // Just count the number of options per expiry
    for (uint i = 0; i < assetLen; ++i) {
      IAccounts.AssetBalance memory currentAsset = assets[i];
      if (address(currentAsset.asset) == address(option)) {
        (uint optionExpiry,, bool isCall) = OptionEncoding.fromSubId(uint96(currentAsset.subId));
        if (optionExpiry < block.timestamp) {
          revert("option expired");
        }

        bool found = false;
        for (uint j = 0; j < seenExpiries; j++) {
          if (expiryCount[j].expiry == optionExpiry) {
            expiryCount[j].optionCount++;
            found = true;
            break;
          }
        }
        if (!found) {
          expiryCount[seenExpiries++] = PortfolioExpiryData({expiry: optionExpiry, optionCount: 1});
        }
      }
    }

    portfolio.expiries = new ExpiryHoldings[](seenExpiries);
    (portfolio.spotPrice, portfolio.minConfidence) = feed.getSpot();
    for (uint i = 0; i < seenExpiries; ++i) {
      (uint forwardPrice, uint confidence1) = futureFeed.getForwardPrice(expiryCount[i].expiry);
      // TODO: rate feed and convert to discount factor
      (uint64 rate, uint confidence2) = interestRateFeed.getInterestRate(expiryCount[i].expiry);
      uint minConfidence = confidence1 < confidence2 ? confidence1 : confidence2;
      minConfidence = portfolio.minConfidence < minConfidence ? portfolio.minConfidence : minConfidence;

      uint secToExpiry = expiryCount[i].expiry - block.timestamp;
      portfolio.expiries[i] = ExpiryHoldings({
        secToExpiry: SafeCast.toUint64(secToExpiry),
        options: new StrikeHolding[](expiryCount[i].optionCount),
        forwardPrice: forwardPrice,
        // vol shocks are added in addPrecomputes
        volShockUp: 0,
        volShockDown: 0,
        mtm: 0,
        fwdShock1MtM: 0,
        fwdShock2MtM: 0,
        staticDiscount: 0,
        rate: uint64(rate),
        discountFactor: uint64(FixedPointMathLib.exp(-int(uint(rate)) * (int(secToExpiry) * 1e18 / 365 days) / 1e18)),
        minConfidence: minConfidence
      });
    }

    // TODO: read from feed
    portfolio.stablePrice = 1e18;

    for (uint i = 0; i < assets.length; ++i) {
      IAccounts.AssetBalance memory currentAsset = assets[i];
      if (address(currentAsset.asset) == address(option)) {
        (uint optionExpiry, uint strike, bool isCall) = OptionEncoding.fromSubId(SafeCast.toUint96(currentAsset.subId));

        uint expiryIndex = findInArray(portfolio.expiries, optionExpiry - block.timestamp, portfolio.expiries.length);

        ExpiryHoldings memory expiry = portfolio.expiries[expiryIndex];

        // insert the calls at the front, and the puts at the end of the options array
        uint index = --expiryCount[expiryIndex].optionCount;

        (uint vol, uint confidence) = volFeed.getVol(SafeCast.toUint128(strike), SafeCast.toUint128(optionExpiry));

        expiry.options[index] = StrikeHolding({
          strike: strike,
          vol: vol,
          amount: currentAsset.balance,
          isCall: isCall,
          minConfidence: confidence < expiry.minConfidence ? confidence : expiry.minConfidence,
          seenInFilter: false
        });
      } else if (address(currentAsset.asset) == address(cashAsset)) {
        portfolio.cash = currentAsset.balance;
      } else if (address(currentAsset.asset) == address(perp)) {
        portfolio.perpPosition = currentAsset.balance;
        portfolio.totalMtM += perp.getUnsettledAndUnrealizedCash(accountId);
      } else if (address(currentAsset.asset) == address(baseAsset)) {
        portfolio.basePosition = SafeCast.toUint256(currentAsset.balance);

        (portfolio.baseValue,) = baseAsset.getValue(portfolio.basePosition, 0, 0);
        portfolio.baseValue = portfolio.baseValue.divideDecimal(portfolio.stablePrice);

        portfolio.totalMtM += SafeCast.toInt256(portfolio.baseValue);
      } else {
        revert("Invalid asset type");
      }
    }

    _addPrecomputes(portfolio, addForwardCont);

    return portfolio;
  }

  function findInArray(ExpiryHoldings[] memory expiryData, uint secToExpiryToFind, uint arrayLen)
    internal
    pure
    returns (uint index)
  {
    unchecked {
      for (uint i; i < arrayLen; ++i) {
        if (expiryData[i].secToExpiry == secToExpiryToFind) {
          return (i);
        }
      }
      revert("secToExpiry not found");
    }
  }

  /////////////////////////////////
  // Scenario independent values //
  /////////////////////////////////

  function _addPrecomputes(IPMRM.PMRM_Portfolio memory portfolio, bool addForwardCont) internal view {
    for (uint i = 0; i < portfolio.expiries.length; ++i) {
      ExpiryHoldings memory expiry = portfolio.expiries[i];
      // Current MtM and forward contingency MtMs

      int expiryMTM = _getExpiryShockedMTM(expiry, 1e18, IPMRM.VolShockDirection.None);
      expiry.mtm += expiryMTM;
      portfolio.totalMtM += expiryMTM;

      if (addForwardCont) {
        int fwd1expMTM = _getExpiryShockedMTM(expiry, contingencyParams.fwdSpotShock1, IPMRM.VolShockDirection.None);
        int fwd2expMTM = _getExpiryShockedMTM(expiry, contingencyParams.fwdSpotShock2, IPMRM.VolShockDirection.None);

        expiry.fwdShock1MtM += fwd1expMTM;
        expiry.fwdShock2MtM += fwd2expMTM;

        int fwdContingency = min(fwd1expMTM, fwd2expMTM) - expiryMTM;

        portfolio.fwdContingency +=
          fwdContingency.multiplyDecimal(int(0.25e18 + 0.01e18 * (expiry.secToExpiry * 1e18 / 365 days) / 1e18));
      }

      portfolio.totalContingency += _calcOptionContingency(expiry, portfolio.spotPrice);

      uint multShock = decPow(
        30 days * 1e18 / (expiry.secToExpiry < 1 days ? 1 days : expiry.secToExpiry),
        expiry.secToExpiry <= 30 days ? volShockParams.shortTermPower : volShockParams.longTermPower
      );

      expiry.volShockUp = 1e18 + volShockParams.volRangeUp.multiplyDecimal(multShock);
      expiry.volShockDown = SafeCast.toUint256(int(1e18) - int(volShockParams.volRangeDown.multiplyDecimal(multShock)));

      // TODO: change to use discount feed value
      expiry.staticDiscount = _getStaticDiscount(expiry.secToExpiry, expiry.rate);
    }

    int otherContingency = int(IntLib.abs(portfolio.perpPosition).multiplyDecimal(contingencyParams.perpPercent));
    otherContingency += int(portfolio.basePosition.multiplyDecimal(contingencyParams.basePercent));
    portfolio.totalContingency += otherContingency.multiplyDecimal(int(portfolio.spotPrice));
  }

  function _calcOptionContingency(ExpiryHoldings memory expiry, uint spotPrice) internal view returns (int) {
    int nakedShorts = 0;
    uint optionsLen = expiry.options.length;
    // As options are sorted as [call, call, ..., put, put], we stop as soon as we see a put (or call in reverse)
    for (uint i = 0; i < optionsLen; ++i) {
      StrikeHolding memory option = expiry.options[i];
      if (option.seenInFilter) {
        continue;
      }
      bool found = false;

      for (uint j = i + 1; j < optionsLen; ++j) {
        StrikeHolding memory option2 = expiry.options[j];

        if (option.strike == option2.strike) {
          option2.seenInFilter = true;

          if (option.amount * option2.amount < 0) {
            // one is negative, one is positive
            int amountCancelled = int(IntLib.absMin(option.amount, option2.amount));
            if (option.amount < 0) {
              nakedShorts += (-option.amount) - amountCancelled;
            } else {
              nakedShorts += (-option2.amount) - amountCancelled;
            }
          } else if (option.amount < 0) {
            // both negative
            nakedShorts += -option.amount - option2.amount;
          }

          found = true;
        }
      }
      if (!found && option.amount < 0) {
        nakedShorts += -option.amount;
      }
    }

    return nakedShorts.multiplyDecimal(pmrmParams.netPosScalar).multiplyDecimal(int(spotPrice));
  }

  ////////////////////////
  // get Initial Margin //
  ////////////////////////

  function _getMargin(IPMRM.PMRM_Portfolio memory portfolio, bool isInitial, Scenario[] memory scenarios)
    internal
    view
    returns (int margin)
  {
    int minSPAN = portfolio.fwdContingency;

    // TODO: better to iterate over spot shocks and vol shocks separately - save on computing otherAsset value
    for (uint i = 0; i < scenarios.length; ++i) {
      Scenario memory scenario = scenarios[i];

      // SPAN value with discounting applied, and only the difference from MtM
      int scenarioMTM = getScenarioMtM(portfolio, scenario);
      if (scenarioMTM < minSPAN) {
        minSPAN = scenarioMTM;
      }
    }

    minSPAN -= portfolio.totalContingency;

    if (isInitial) {
      uint mFactor = 1.3e18;
      if (portfolio.stablePrice < 0.98e18) {
        mFactor += (0.98e18 - portfolio.stablePrice).multiplyDecimal(pmrmParams.pegLossFactor);
      }
      minSPAN = minSPAN.multiplyDecimal(int(mFactor));
    }

    minSPAN += portfolio.totalMtM + portfolio.cash;

    return minSPAN;
  }

  function getScenarioMtM(PMRM_Portfolio memory portfolio, Scenario memory scenario)
    internal
    view
    returns (int scenarioMtM)
  {
    for (uint j = 0; j < portfolio.expiries.length; ++j) {
      ExpiryHoldings memory expiry = portfolio.expiries[j];

      int expiryMtM;
      // Check cached values
      if (scenario.volShock == IPMRM.VolShockDirection.None && scenario.spotShock == 1e18) {
        // we've already calculated this previously, so just use that
        expiryMtM = expiry.mtm;
      } else if (
        scenario.volShock == IPMRM.VolShockDirection.None && scenario.spotShock == contingencyParams.fwdSpotShock1
      ) {
        expiryMtM = expiry.fwdShock1MtM;
      } else if (
        scenario.volShock == IPMRM.VolShockDirection.None && scenario.spotShock == contingencyParams.fwdSpotShock1
      ) {
        expiryMtM = expiry.fwdShock2MtM;
      } else {
        expiryMtM = _getExpiryShockedMTM(expiry, scenario.spotShock, scenario.volShock);
      }

      // we subtract expiry MtM as we only care about the difference from the current mtm at this stage
      scenarioMtM += _applyMTMDiscount(expiryMtM, expiry.staticDiscount) - expiry.mtm;
    }

    int otherAssetValue;

    (uint baseValue,) = baseAsset.getValue(portfolio.basePosition, scenario.spotShock, 0);

    int shockedBaseValue = SafeCast.toInt256(baseValue.divideDecimal(portfolio.stablePrice));
    int shockedPerpValue = _getShockedPerpValue(portfolio.perpPosition, portfolio.spotPrice, scenario.spotShock);

    scenarioMtM += (shockedBaseValue + shockedPerpValue - SafeCast.toInt256(portfolio.baseValue));
  }

  function _checkMargin(IPMRM.PMRM_Portfolio memory portfolio, IPMRM.Scenario[] memory scenarios) internal view {
    int im = _getMargin(portfolio, true, scenarios);
    int margin = portfolio.cash + im;
    if (margin < 0) {
      revert("IM rules not satisfied");
    }
  }

  function _applyMTMDiscount(int expiryMTM, uint staticDiscount) internal pure returns (int) {
    if (expiryMTM > 0) {
      return expiryMTM * SafeCast.toInt256(staticDiscount) / 1e18;
    } else {
      return expiryMTM;
    }
  }

  function _getStaticDiscount(uint secToExpiry, uint rate) internal view returns (uint staticDiscount) {
    uint tAnnualised = secToExpiry * 1e18 / 365 days;
    uint shockRFR = rate.multiplyDecimal(4e18) + 0.05e18;
    return 0.95e18 * FixedPointMathLib.exp(-SafeCast.toInt256(tAnnualised.multiplyDecimal(shockRFR))) / 1e18;
  }

  function _getShockedBaseAssetValue(uint position, uint spotPrice, uint spotShock) internal pure returns (uint) {
    uint value = spotPrice.multiplyDecimal(spotShock);
    return position.multiplyDecimal(value);
  }

  function _getShockedPerpValue(int position, uint spotPrice, uint spotShock) internal pure returns (int) {
    int value = (int(spotShock) - SignedDecimalMath.UNIT).multiplyDecimal(int(spotPrice));
    return position.multiplyDecimal(value);
  }

  /////////////
  // Helpers //
  /////////////

  // calculate MTM with given shock
  function _getExpiryShockedMTM(ExpiryHoldings memory expiry, uint spotShock, IPMRM.VolShockDirection volShockDirection)
    internal
    view
    returns (int mtm)
  {
    uint volShock = 1e18;
    if (volShockDirection == VolShockDirection.Up) {
      volShock = expiry.volShockUp;
    } else if (volShockDirection == VolShockDirection.Down) {
      volShock = expiry.volShockDown;
    }

    mtm = 0;
    // Iterate over all the calls in the expiry
    for (uint i = 0; i < expiry.options.length; i++) {
      StrikeHolding memory option = expiry.options[i];

      // Calculate the black scholes value of the call
      mtm += mtmCache.getMTM(
        SafeCast.toUint128(option.strike),
        SafeCast.toUint64(expiry.secToExpiry),
        SafeCast.toUint128(expiry.forwardPrice.multiplyDecimal(spotShock)),
        SafeCast.toUint128(option.vol.multiplyDecimal(volShock)),
        expiry.discountFactor,
        option.amount,
        option.isCall
      );
    }
  }

  //////////
  // View //
  //////////

  function arrangePortfolio(IAccounts.AssetBalance[] memory assets)
    external
    view
    returns (IPMRM.PMRM_Portfolio memory portfolio)
  {
    // TODO: pass in account Id
    return _arrangePortfolio(0, assets, true);
  }

  function getMargin(IAccounts.AssetBalance[] memory assets, bool isInitial) external view returns (int) {
    // TODO: pass in account Id
    IPMRM.PMRM_Portfolio memory portfolio = _arrangePortfolio(0, assets, true);
    int im = _getMargin(portfolio, isInitial, marginScenarios);
    return im;
  }

  function mergeAccounts(uint mergeIntoId, uint[] memory mergeFromIds) external {
    address owner = accounts.ownerOf(mergeIntoId);
    for (uint i = 0; i < mergeFromIds.length; ++i) {
      // check owner of all accounts is the same - note this ignores
      if (owner != accounts.ownerOf(mergeFromIds[i])) {
        revert("accounts not owned by same address");
      }
      // Move all assets of the other
      IAccounts.AssetBalance[] memory assets = accounts.getAccountBalances(mergeFromIds[i]);
      for (uint j = 0; j < assets.length; ++j) {
        _symmetricManagerAdjustment(
          mergeFromIds[i], mergeIntoId, assets[j].asset, SafeCast.toUint96(assets[j].subId), assets[j].balance
        );
      }
    }
  }

  ////////////////////////
  //    Account Hooks   //
  ////////////////////////

  /**
   * @notice Ensures new manager is valid.
   * @param newManager IManager to change account to.
   */
  function handleManagerChange(uint, IManager newManager) external view {}

  ////////////////////////
  //      Modifiers     //
  ////////////////////////

  modifier onlyAccounts() {
    if (msg.sender != address(accounts)) {
      revert("only accounts");
    }
    _;
  }

  // TODO: move to IntLib
  function min(int a, int b) internal pure returns (int) {
    return (a < b) ? a : b;
  }

  function min(uint a, uint b) internal pure returns (uint) {
    return (a < b) ? a : b;
  }

  function decPow(uint a, uint b) internal pure returns (uint) {
    return FixedPointMathLib.exp(FixedPointMathLib.ln(SafeCast.toInt256(a)) * SafeCast.toInt256(b) / 1e18);
  }
}
