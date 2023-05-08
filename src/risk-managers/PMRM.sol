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
import "src/interfaces/IDiscountFactorFeed.sol";

import "./BaseManager.sol";

import "forge-std/console2.sol";
import "../interfaces/IMarginAsset.sol";

interface IPMRM {
  enum VolShockDirection {
    None,
    Up,
    Down
  }

  struct PMRMParameters {
    int staticDiscount;
    int lossFactor;
    uint epsilon;
    uint fwdStep;
    int netPosScalar;
    uint reservation;
  }

  struct VolShockParameters {
    uint volRangeUp;
    uint volRangeDown;
    uint upShift;
    uint downShift;
    uint c_up;
    uint c_min;
  }

  struct ContingencyParameters {
    uint basePercent;

    uint perpPercent;

    uint optionPercent;

    uint fwdSpotShock1;
    uint fwdSpotShock2;
    uint fwdScalingFactor;
    // <7 dte
    uint fwdShortFactor;
    // >7dte <28dte
    uint fwdMediumFactor;
    // >28dte
    uint fwdLongFactor;

    uint oracleConfMargin;
    uint oracleSpotConfThreshold;
    uint oracleVolConfThreshold;
    uint oracleFutureConfThreshold;
    uint oracleDiscountConfThreshold;
  }

  struct PMRM_Portfolio {
    uint spotPrice;
    /// cash amount or debt
    int cash;
    /// option holdings per expiry
    ExpiryHoldings[] expiries;
    int perpPosition;
    uint basePosition;

    // Calculated values
    int mtm;
    int fwdShock1MtM;
    int fwdShock2MtM;
    int fwdContingency;
    // option + base + perp; excludes fwd/oracle
    int totalContingency;
  }

  struct OtherAssets {
    IMarginAsset asset;
    int amount;
  }

  struct ExpiryHoldings {
    uint expiry;
    StrikeHolding[] options;
    uint forwardPrice;
    uint volShockUp;
    uint volShockDown;
    uint minVol;
  }

  struct StrikeHolding {
    /// strike price of held options
    uint strike;
    uint vol;
    int amount;
    bool isCall;
  }

  struct PortfolioExpiryData {
    uint expiry;
    uint callCount;
    uint putCount;
  }

  struct Scenario {
    uint spotShock; // i.e. 1.2e18 = 20% spot shock up
    VolShockDirection volShock; // i.e. [Up, Down, None]
  }
}

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
  IDiscountFactorFeed public discountFactorFeed;
  IVolFeed public volFeed;

  IMarginAsset public immutable baseAsset;

  /// @dev Pricing module to get option mark-to-market price
  MTMCache public mtmCache;

  /// @dev Portfolio Margin Parameters: maintenance and initial margin requirements
  IPMRM.PMRMParameters public pmrmParams;
  IPMRM.VolShockParameters public volShockParams;
  IPMRM.ContingencyParameters public contingencyParams;
  IPMRM.Scenario[] public scenarios;

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
    ISpotFeed spotFeed_,
    MTMCache mtmCache_,
    IDiscountFactorFeed discountFactorFeed_,
    IVolFeed volFeed_,
    IMarginAsset baseAsset_
  )
    BaseManager(accounts_, futureFeed_, settlementFeed_, cashAsset_, option_, perp_)
  {
    feed = spotFeed_;
    mtmCache = mtmCache_;
    discountFactorFeed = discountFactorFeed_;
    volFeed = volFeed_;
    baseAsset = baseAsset_;

    pmrmParams.staticDiscount = 0.9e18;
    pmrmParams.lossFactor = 1.3e18;
    pmrmParams.epsilon = 0.05e18;
    pmrmParams.fwdStep = 0.01e18;
    pmrmParams.netPosScalar = 0.01e18;
    pmrmParams.reservation = 1e18;

    volShockParams.volRangeUp = 1e18;
    volShockParams.volRangeDown = 0.7e18;
    volShockParams.upShift = 0.294e18;
    volShockParams.downShift = 0.187e18;
    volShockParams.c_up = 0.30e18;
    volShockParams.c_min = 0.1e18;

    contingencyParams.basePercent = 0.02e18;
    contingencyParams.perpPercent = 0.02e18;
    contingencyParams.optionPercent = 0.01e18;
    contingencyParams.fwdSpotShock1 = 0.95e18;
    contingencyParams.fwdSpotShock2 = 1.05e18;
    contingencyParams.fwdScalingFactor = 0.5e18;

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
      if (scenarios.length <= i) {
        scenarios.push(_scenarios[i]);
      } else {
        scenarios[i] = _scenarios[i];
      }
    }
    for (uint i = _scenarios.length; i < scenarios.length; i++) {
      delete scenarios[i];
    }
  }

  /**
   * @notice Set the maintenance margin requirement
   */
  function setPMRMParameters(IPMRM.PMRMParameters memory _pmrmParameters) external onlyOwner {
    pmrmParams = _pmrmParameters;
  }

  function setDiscountFactorFeed(IDiscountFactorFeed _discountFactorFeed) external onlyOwner {
    discountFactorFeed = _discountFactorFeed;
  }

  function setMTMCache(MTMCache _mtmCache) external onlyOwner {
    mtmCache = _mtmCache;
  }

  ///////////////////////
  //   Account Hooks   //
  ///////////////////////

  /**
   * @notice Ensures asset is valid and Max Loss margin is met.
   * @param accountId Account for which to check trade.
   */
  function handleAdjustment(uint accountId, uint tradeId, address, AssetDelta[] calldata assetDeltas, bytes memory)
    public
    onlyAccounts
  {
  //   _chargeOIFee(accountId, tradeId, assetDeltas);
  //
  //    // check assets are only cash and perp
  //   for (uint i = 0; i < assetDeltas.length; i++) {
  //     if (assetDeltas[i].asset == perp) {
  //       // settle perps if the user has perp position
  //       _settleAccountPerps(accountId);
  //     } else if (assetDeltas[i].asset != cashAsset && assetDeltas[i].asset != option) {
  //       revert("unsupported asset");
  //     }
  //   }
  //
  //   IPMRM.PMRM_Portfolio memory portfolio = _arrangePortfolio(accounts.getAccountBalances(accountId));
  //
  //   _checkMargin(portfolio);
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
  function _arrangePortfolio(IAccounts.AssetBalance[] memory assets)
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
        bool found = false;
        for (uint j = 0; j < seenExpiries; j++) {
          if (expiryCount[j].expiry == optionExpiry) {
            if (isCall) {
              expiryCount[j].callCount++;
            } else {
              expiryCount[j].putCount++;
            }
            found = true;
            break;
          }
        }
        if (!found) {
          expiryCount[seenExpiries++] =
            PortfolioExpiryData({expiry: optionExpiry, callCount: isCall ? 1 : 0, putCount: isCall ? 0 : 1});
        }
      }
    }

    portfolio.expiries = new ExpiryHoldings[](seenExpiries);
    (portfolio.spotPrice, ) = feed.getSpot();
    for (uint i = 0; i < seenExpiries; ++i) {
      (uint forwardPrice, uint confidence) = futureFeed.getFuturePrice(expiryCount[i].expiry);
      // TODO: confidence
      portfolio.expiries[i] = ExpiryHoldings({
        expiry: expiryCount[i].expiry,
        options: new StrikeHolding[](expiryCount[i].callCount + expiryCount[i].putCount),
        forwardPrice: forwardPrice,
        volShockUp: 0,
        volShockDown: 0,
        minVol: type(uint).max
      });
    }

    for (uint i = 0; i < assets.length; ++i) {
      IAccounts.AssetBalance memory currentAsset = assets[i];
      if (address(currentAsset.asset) == address(option)) {
        (uint optionExpiry, uint strike, bool isCall) = OptionEncoding.fromSubId(SafeCast.toUint96(currentAsset.subId));

        uint expiryIndex = findInArray(portfolio.expiries, optionExpiry, portfolio.expiries.length);

        ExpiryHoldings memory expiry = portfolio.expiries[expiryIndex];

        // insert the calls at the front, and the puts at the end of the options array
        uint index = isCall
          ? --expiryCount[expiryIndex].callCount // start in the middle and go to 0
          : expiry.options.length - (expiryCount[expiryIndex].putCount--); // start at the middle and go to length - 1

        (uint vol, uint confidence) = volFeed.getVol(SafeCast.toUint128(strike), SafeCast.toUint128(optionExpiry));
        // TODO: confidence
        expiry.options[index] = StrikeHolding({
          strike: strike,
          vol: vol,
          amount: currentAsset.balance,
          isCall: isCall
        });
        expiry.minVol = min(expiry.minVol, vol);

      } else if (address(currentAsset.asset) == address(cashAsset)) {
        portfolio.cash = currentAsset.balance;
      } else if (address(currentAsset.asset) == address(perp)) {
        portfolio.perpPosition = currentAsset.balance;
      } else if (address(currentAsset.asset) == address(baseAsset)) {
        portfolio.basePosition = SafeCast.toUint256(currentAsset.balance);
      } else {
        revert("Invalid asset type");
      }
    }

    _addPrecomputes(portfolio);

    return portfolio;
  }

  function findInArray(ExpiryHoldings[] memory expiryData, uint expiryToFind, uint arrayLen)
    internal
    pure
    returns (uint index)
  {
    unchecked {
      for (uint i; i < arrayLen; ++i) {
        if (expiryData[i].expiry == expiryToFind) {
          return (i);
        }
      }
      revert("expiry not found");
    }
  }

  /////////////////////////////////
  // Scenario independent values //
  /////////////////////////////////

  function _addPrecomputes(IPMRM.PMRM_Portfolio memory portfolio) internal view {
    for (uint i = 0; i < portfolio.expiries.length; ++i) {
      ExpiryHoldings memory expiry = portfolio.expiries[i];
      // Current MtM and forward contingency MtMs

      int expiryMTM = _getExpiryShockedMTM(expiry, 1e18, IPMRM.VolShockDirection.None);
      int fwd1expMTM = _getExpiryShockedMTM(expiry, contingencyParams.fwdSpotShock1, IPMRM.VolShockDirection.None);
      int fwd2expMTM = _getExpiryShockedMTM(expiry, contingencyParams.fwdSpotShock2, IPMRM.VolShockDirection.None);

      portfolio.mtm += expiryMTM;
      portfolio.fwdShock1MtM += fwd1expMTM;
      portfolio.fwdShock2MtM += fwd2expMTM;

      int fwdContingency = -int(IntLib.abs(min(fwd1expMTM, fwd2expMTM) - expiryMTM) * contingencyParams.fwdScalingFactor / 1e18);
      uint tte = expiry.expiry - block.timestamp;
      if (tte < 7 days) {
        fwdContingency = fwdContingency.multiplyDecimal(int(contingencyParams.fwdShortFactor));
      } else if (tte < 28 days) {
        fwdContingency = fwdContingency.multiplyDecimal(int(contingencyParams.fwdMediumFactor));
      } else {
        fwdContingency = fwdContingency.multiplyDecimal(int(contingencyParams.fwdLongFactor));
      }

      portfolio.fwdContingency += fwdContingency;

      portfolio.totalContingency += _calcOptionContingency(expiry, portfolio.spotPrice);

      uint sqrtDTE = FixedPointMathLib.sqrt(expiry.expiry - block.timestamp);
      expiry.volShockUp = (volShockParams.volRangeUp).divideDecimalRound(sqrtDTE) + volShockParams.upShift;
      expiry.volShockDown = (volShockParams.volRangeDown).divideDecimalRound(sqrtDTE) + volShockParams.downShift;
    }

    // TODO: this might not work with USDC feed
    int otherContingency = int(IntLib.abs(portfolio.perpPosition).multiplyDecimal(contingencyParams.perpPercent));
    otherContingency += int(portfolio.basePosition.multiplyDecimal(contingencyParams.basePercent));
    portfolio.totalContingency += otherContingency.multiplyDecimal(int(portfolio.spotPrice));
  }

  function _calcOptionContingency(ExpiryHoldings memory expiry, uint spotPrice) internal view returns (int) {
    int netShortPosPerStrike = 0;
    uint optionsLen = expiry.options.length;
    // As options are sorted as [call, call, ..., put, put], we stop as soon as we see a put (or call in reverse)
    for (uint i = 0; i < optionsLen; ++i) {
      StrikeHolding memory call = expiry.options[i];
      if (!call.isCall) {
        break;
      }
      for (uint j = optionsLen - 1; j >= 0; --j) {
        StrikeHolding memory put = expiry.options[j];
        if (put.isCall) {
          break;
        }
        if (put.strike == call.strike) {
          int tot = call.amount + put.amount;
          netShortPosPerStrike += tot < 0 ? tot : int(0);
        }
      }
    }

    return netShortPosPerStrike.multiplyDecimal(pmrmParams.netPosScalar).multiplyDecimal(int(spotPrice));
  }

  ////////////////////////
  // get Initial Margin //
  ////////////////////////

  function _getIM(IPMRM.PMRM_Portfolio memory portfolio) internal view returns (int) {
    int minMargin = type(int).max;

    // TODO: better to iterate over spot shocks and vol shocks separately - save on computing otherAsset value
    for (uint i = 0; i < scenarios.length; ++i) {
      Scenario memory scenario = scenarios[i];

      int scenarioMTM = 0;

      if (scenario.volShock == IPMRM.VolShockDirection.None && scenario.spotShock == 1e18) {
        // we've already calculated this previously, so just use that
        scenarioMTM = _applyMTMDiscount(portfolio.mtm);
      } else if (scenario.volShock == IPMRM.VolShockDirection.None && scenario.spotShock == contingencyParams.fwdSpotShock1) {
        scenarioMTM = _applyMTMDiscount(portfolio.fwdShock1MtM);
      } else if (scenario.volShock == IPMRM.VolShockDirection.None && scenario.spotShock == contingencyParams.fwdSpotShock1) {
        scenarioMTM = _applyMTMDiscount(portfolio.fwdShock2MtM);
      } else {
        for (uint j = 0; j < portfolio.expiries.length; ++j) {
          ExpiryHoldings memory expiry = portfolio.expiries[j];
          scenarioMTM += _applyMTMDiscount(_getExpiryShockedMTM(expiry, scenario.spotShock, scenario.volShock));
        }
      }

      // TODO: this is old need to revisit
      int scenarioLoss = (scenarioMTM - portfolio.mtm + portfolio.totalContingency).multiplyDecimal(pmrmParams.lossFactor);

      int otherAssetValue;

      otherAssetValue += SafeCast.toInt256(
        _getShockedBaseAssetValue(portfolio.basePosition, portfolio.spotPrice, scenario.spotShock)
      );
      // TODO: missing realised PnL, funding etc. should be stored in portfolio when struct is generated/arranged
      otherAssetValue += _getShockedPerpValue(portfolio.perpPosition, portfolio.spotPrice, scenario.spotShock);

      scenarioMTM += otherAssetValue + scenarioLoss;

      if (scenarioMTM < minMargin) {
        minMargin = scenarioMTM;
      }
    }

    if (minMargin > 0) {
      return 0;
    }
    return minMargin - int(pmrmParams.reservation);
  }

  function _checkMargin(IPMRM.PMRM_Portfolio memory portfolio) internal view {
    int im = _getIM(portfolio);
    int margin = portfolio.cash + im;
    if (margin < 0) {
      revert("IM rules not satisfied");
    }
  }

  function _applyMTMDiscount(int expiryMTM) internal view returns (int) {
    if (expiryMTM > 0) {
      // TODO: * e^-shockRFR*TimeToExpiry
      return expiryMTM * pmrmParams.staticDiscount / 1e18;
    } else {
      return expiryMTM;
    }
  }

  function _getShockedBaseAssetValue(uint position, uint spotPrice, uint spotShock) internal pure returns (uint) {
    uint value = spotPrice.multiplyDecimal(spotShock);
    return position.multiplyDecimal(value);
  }

  function _getShockedPerpValue(int position, uint spotPrice, uint spotShock) internal pure returns (int) {
    // TODO: account for unrealised perpPnL and funding (in the portfolio arranging step)
    int value = (int(spotShock) - SignedDecimalMath.UNIT).multiplyDecimal(int(spotPrice));
    return position.multiplyDecimal(value);
  }

  /////////////
  // Helpers //
  /////////////

  // calculate MTM with given shock
  function _getExpiryShockedMTM(ExpiryHoldings memory expiry, uint spotShock, IPMRM.VolShockDirection volShockDirection) internal view returns (int mtm) {
    // TODO: catch low confidence and add contingency
    (uint64 discountFactor, uint confidence) = discountFactorFeed.getDiscountFactor(expiry.expiry);

    if (expiry.expiry < block.timestamp) {
      // TODO: calculate settlement value of option
      revert("Option already expired");
    }

    // TODO: this shock is out of date
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
        SafeCast.toUint64(expiry.expiry),
        SafeCast.toUint128(expiry.forwardPrice.multiplyDecimal(spotShock)),
        // TODO: cap when shocking up, floor when shocking down
        SafeCast.toUint128(option.vol.multiplyDecimal(volShock)),
        discountFactor,
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
    return _arrangePortfolio(assets);
  }

  function getIM(IAccounts.AssetBalance[] memory assets) external view returns (int) {
    IPMRM.PMRM_Portfolio memory portfolio = _arrangePortfolio(assets);
    int im = _getIM(portfolio);
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
        _symmetricManagerAdjustment(mergeFromIds[i], mergeIntoId, assets[j].asset, SafeCast.toUint96(assets[j].subId), assets[j].balance);
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
  // TODO: move to libs
  function min(uint a, uint b) internal pure returns (uint) {
    return (a < b) ? a : b;
  }
}
