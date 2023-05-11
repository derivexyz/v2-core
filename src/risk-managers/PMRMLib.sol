import "../interfaces/IPMRM.sol";
import "../interfaces/IMTMCache.sol";
import "lyra-utils/decimals/SignedDecimalMath.sol";
import "lyra-utils/decimals/DecimalMath.sol";

import "openzeppelin/access/Ownable2Step.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "./TODO_MOVE_TO_LYRA_UTILS.sol";
import "lyra-utils/math/IntLib.sol";
import "../interfaces/IAccounts.sol";

contract IPMRMLib {
  struct VolShockParameters {
    uint volRangeUp;
    uint volRangeDown;
    uint shortTermPower;
    uint longTermPower;
  }

  struct StaticDiscountParameters {
    uint rateMultiplicativeFactor;
    uint rateAdditiveFactor;
    uint baseStaticDiscount;
  }

  struct ForwardContingencyParameters {
    uint spotShock1;
    uint spotShock2;
    uint additiveFactor;
    uint multiplicativeFactor;
  }

  struct OtherContingencyParameters {
    uint pegLossThreshold;
    uint pegLossFactor;
    uint confidenceThreshold;
    uint basePercent;
    uint perpPercent;
    /// @dev Factor for multiplying number of naked shorts (per strike) in the portfolio
    uint optionPercent;
  }
}

contract PMRMLib is IPMRMLib, Ownable2Step {
  using SignedDecimalMath for int;
  using DecimalMath for uint;
  using SafeCast for uint;

  /// @dev Pricing module to get option mark-to-market price
  IMTMCache public mtmCache;

  IPMRMLib.ForwardContingencyParameters fwdContParams;
  IPMRMLib.OtherContingencyParameters otherContParams;
  IPMRMLib.StaticDiscountParameters staticDiscountParams;
  IPMRMLib.VolShockParameters volShockParams;

  constructor(IMTMCache _mtmCache) Ownable2Step() {
    mtmCache = _mtmCache;

    fwdContParams.spotShock1 = 0.95e18;
    fwdContParams.spotShock2 = 1.05e18;
    fwdContParams.additiveFactor = 0.25e18;
    fwdContParams.multiplicativeFactor = 0.01e18;

    otherContParams.pegLossThreshold = 0.98e18;
    otherContParams.pegLossFactor = 0.01e18;
    otherContParams.confidenceThreshold = 0.95e18;
    otherContParams.basePercent = 0.02e18;
    otherContParams.perpPercent = 0.02e18;
    otherContParams.optionPercent = 0.01e18;

    staticDiscountParams.baseStaticDiscount = 0.95e18;
    staticDiscountParams.rateMultiplicativeFactor = 4e18;
    staticDiscountParams.rateAdditiveFactor = 0.05e18;

    volShockParams.volRangeUp = 0.45e18;
    volShockParams.volRangeDown = 0.3e18;
    volShockParams.shortTermPower = 0.3e18;
    volShockParams.longTermPower = 0.13e18;
  }

  ///////////
  // Admin //
  ///////////

  function setMTMCache(IMTMCache _mtmCache) external onlyOwner {
    mtmCache = _mtmCache;
  }

  //////////////////////
  // MTM calculations //
  //////////////////////

  function _getMargin(IPMRM.PMRM_Portfolio memory portfolio, bool isInitial, IPMRM.Scenario[] memory scenarios)
    internal
    view
    returns (int margin)
  {
    int minSPAN = portfolio.fwdContingency;

    for (uint i = 0; i < scenarios.length; ++i) {
      IPMRM.Scenario memory scenario = scenarios[i];

      // SPAN value with discounting applied, and only the difference from MtM
      int scenarioMTM = getScenarioMtM(portfolio, scenario);
      if (scenarioMTM < minSPAN) {
        minSPAN = scenarioMTM;
      }
    }

    minSPAN -= SafeCast.toInt256(portfolio.staticContingency);

    if (isInitial) {
      minSPAN -= SafeCast.toInt256(portfolio.confidenceContingency);

      uint mFactor = 1.3e18;
      if (portfolio.stablePrice < otherContParams.pegLossThreshold) {
        mFactor +=
          (otherContParams.pegLossThreshold - portfolio.stablePrice).multiplyDecimal(otherContParams.pegLossFactor);
      }

      minSPAN = minSPAN.multiplyDecimal(int(mFactor));
    }

    minSPAN += portfolio.totalMtM + portfolio.cash;

    return minSPAN;
  }

  function getScenarioMtM(IPMRM.PMRM_Portfolio memory portfolio, IPMRM.Scenario memory scenario)
    internal
    view
    returns (int scenarioMtM)
  {
    for (uint j = 0; j < portfolio.expiries.length; ++j) {
      IPMRM.ExpiryHoldings memory expiry = portfolio.expiries[j];

      int expiryMtM;
      // Check cached values
      if (scenario.volShock == IPMRM.VolShockDirection.None && scenario.spotShock == 1e18) {
        // we've already calculated this previously, so just use that
        expiryMtM = expiry.mtm;
      } else if (scenario.volShock == IPMRM.VolShockDirection.None && scenario.spotShock == fwdContParams.spotShock1) {
        // NOTE: this value may not be cached depending on how _addPrecomputes was called; so be careful.
        expiryMtM = expiry.fwdShock1MtM;
      } else if (scenario.volShock == IPMRM.VolShockDirection.None && scenario.spotShock == fwdContParams.spotShock2) {
        // NOTE: this value may not be cached depending on how _addPrecomputes was called; so be careful.
        expiryMtM = expiry.fwdShock2MtM;
      } else {
        expiryMtM = _getExpiryShockedMTM(expiry, scenario.spotShock, scenario.volShock);
      }

      // we subtract expiry MtM as we only care about the difference from the current mtm at this stage
      scenarioMtM += _applyMTMDiscount(expiryMtM, expiry.staticDiscount) - expiry.mtm;
    }

    int shockedBaseValue = SafeCast.toInt256(
      _getBaseValue(portfolio.basePosition, portfolio.spotPrice, portfolio.stablePrice, scenario.spotShock)
    );
    int shockedPerpValue = _getShockedPerpValue(portfolio.perpPosition, portfolio.spotPrice, scenario.spotShock);

    scenarioMtM += (shockedBaseValue + shockedPerpValue - SafeCast.toInt256(portfolio.baseValue));
  }

  // calculate MTM with given shock
  function _getExpiryShockedMTM(
    IPMRM.ExpiryHoldings memory expiry,
    uint spotShock,
    IPMRM.VolShockDirection volShockDirection
  ) internal view returns (int mtm) {
    uint volShock = 1e18;
    if (volShockDirection == IPMRM.VolShockDirection.Up) {
      volShock = expiry.volShockUp;
    } else if (volShockDirection == IPMRM.VolShockDirection.Down) {
      volShock = expiry.volShockDown;
    }

    IMTMCache.Expiry memory expiryDetails = IMTMCache.Expiry({
      secToExpiry: SafeCast.toUint64(expiry.secToExpiry),
      forwardPrice: SafeCast.toUint128(expiry.forwardPrice.multiplyDecimal(spotShock)),
      discountFactor: expiry.discountFactor
    });

    IMTMCache.Option[] memory optionDetails = new IMTMCache.Option[](expiry.options.length);
    for (uint i = 0; i < expiry.options.length; i++) {
      IPMRM.StrikeHolding memory option = expiry.options[i];
      optionDetails[i] = IMTMCache.Option({
        strike: SafeCast.toUint128(option.strike),
        vol: SafeCast.toUint128(option.vol.multiplyDecimal(volShock)),
        amount: option.amount,
        isCall: option.isCall
      });
    }
    return mtmCache.getExpiryMTM(expiryDetails, optionDetails);
  }

  function _applyMTMDiscount(int expiryMTM, uint staticDiscount) internal pure returns (int) {
    if (expiryMTM > 0) {
      return expiryMTM * SafeCast.toInt256(staticDiscount) / 1e18;
    } else {
      return expiryMTM;
    }
  }

  function _getShockedPerpValue(int position, uint spotPrice, uint spotShock) internal pure returns (int) {
    int value = (int(spotShock) - SignedDecimalMath.UNIT).multiplyDecimal(int(spotPrice));
    return position.multiplyDecimal(value);
  }

  function _getBaseValue(uint position, uint spot, uint stablePrice, uint spotShock) internal pure returns (uint) {
    return position.multiplyDecimal(spot).multiplyDecimal(spotShock).divideDecimal(stablePrice);
  }

  function _getDiscountFactor(int rate, uint secToExpiry) internal view returns (uint64) {
    return uint64(FixedPointMathLib.exp(-rate * (int(secToExpiry) * 1e18 / 365 days) / 1e18));
  }

  /////////////////
  // Precomputes //
  /////////////////
  // Precomputes are values used within SPAN for all shocks, so we only calculate them once

  function _addPrecomputes(IPMRM.PMRM_Portfolio memory portfolio, bool addForwardCont) internal view {
    portfolio.baseValue = _getBaseValue(portfolio.basePosition, portfolio.spotPrice, portfolio.stablePrice, 1e18);
    portfolio.totalMtM += SafeCast.toInt256(portfolio.baseValue);
    portfolio.totalMtM += portfolio.unrealisedPerpValue;

    uint staticContingency = IntLib.abs(portfolio.perpPosition).multiplyDecimal(otherContParams.perpPercent);
    staticContingency += portfolio.basePosition.multiplyDecimal(otherContParams.basePercent);
    portfolio.staticContingency = staticContingency.multiplyDecimal(portfolio.spotPrice);

    for (uint i = 0; i < portfolio.expiries.length; ++i) {
      IPMRM.ExpiryHoldings memory expiry = portfolio.expiries[i];
      // Current MtM and forward contingency MtMs

      expiry.mtm = _getExpiryShockedMTM(expiry, 1e18, IPMRM.VolShockDirection.None);
      portfolio.totalMtM += expiry.mtm;

      if (addForwardCont) {
        _addForwardContingency(portfolio, expiry);
      }

      _addVolShocks(expiry);
      _addStaticDiscount(expiry);

      portfolio.staticContingency += _getOptionContingency(expiry, portfolio.spotPrice);
      portfolio.confidenceContingency += _getConfidenceContingency(expiry, portfolio.spotPrice);
    }
  }

  function _addStaticDiscount(IPMRM.ExpiryHoldings memory expiry) internal view {
    uint tAnnualised = expiry.secToExpiry * 1e18 / 365 days;
    uint cappedRate = expiry.rate < 0 ? 0 : uint(int(expiry.rate));
    uint shockRFR = uint(cappedRate).multiplyDecimal(staticDiscountParams.rateMultiplicativeFactor)
      + staticDiscountParams.rateAdditiveFactor;
    expiry.staticDiscount = staticDiscountParams.baseStaticDiscount.multiplyDecimal(
      FixedPointMathLib.exp(-SafeCast.toInt256(tAnnualised.multiplyDecimal(shockRFR)))
    );
  }

  function _addVolShocks(IPMRM.ExpiryHoldings memory expiry) internal view {
    uint tao = 30 days * 1e18 / TODO_MOVE_TO_LYRA_UTILS.max(expiry.secToExpiry, 1 days);
    uint multShock = TODO_MOVE_TO_LYRA_UTILS.decPow(
      tao, expiry.secToExpiry <= 30 days ? volShockParams.shortTermPower : volShockParams.longTermPower
    );

    expiry.volShockUp = 1e18 + volShockParams.volRangeUp.multiplyDecimal(multShock);
    expiry.volShockDown = SafeCast.toUint256(int(1e18) - int(volShockParams.volRangeDown.multiplyDecimal(multShock)));
  }

  ///////////////////
  // Contingencies //
  ///////////////////

  function _addForwardContingency(IPMRM.PMRM_Portfolio memory portfolio, IPMRM.ExpiryHoldings memory expiry)
    internal
    view
  {
    int fwd1expMTM = _getExpiryShockedMTM(expiry, fwdContParams.spotShock1, IPMRM.VolShockDirection.None);
    int fwd2expMTM = _getExpiryShockedMTM(expiry, fwdContParams.spotShock2, IPMRM.VolShockDirection.None);

    expiry.fwdShock1MtM += fwd1expMTM;
    expiry.fwdShock2MtM += fwd2expMTM;

    int fwdContingency = TODO_MOVE_TO_LYRA_UTILS.min(fwd1expMTM, fwd2expMTM) - expiry.mtm;
    int fwdContingencyFactor = int(
      fwdContParams.additiveFactor //
        + fwdContParams.multiplicativeFactor.multiplyDecimal(TODO_MOVE_TO_LYRA_UTILS.annualize(expiry.secToExpiry))
    );
    portfolio.fwdContingency += fwdContingency.multiplyDecimal(fwdContingencyFactor);
  }

  function _getConfidenceContingency(IPMRM.ExpiryHoldings memory expiry, uint spotPrice) internal view returns (uint) {
    if (expiry.minConfidence < otherContParams.confidenceThreshold) {
      return (1e18 - expiry.minConfidence).multiplyDecimal(expiry.netOptions);
    }
    return 0;
  }

  function _getOptionContingency(IPMRM.ExpiryHoldings memory expiry, uint spotPrice) internal view returns (uint) {
    uint nakedShorts = 0;
    uint optionsLen = expiry.options.length;
    for (uint i = 0; i < optionsLen; ++i) {
      IPMRM.StrikeHolding memory option = expiry.options[i];
      if (option.seenInFilter) {
        continue;
      }
      bool found = false;

      for (uint j = i + 1; j < optionsLen; ++j) {
        IPMRM.StrikeHolding memory option2 = expiry.options[j];

        if (option.strike == option2.strike) {
          option2.seenInFilter = true;

          if (option.amount * option2.amount < 0) {
            // one is negative, one is positive
            uint amountCancelled = IntLib.absMin(option.amount, option2.amount);
            if (option.amount < 0) {
              nakedShorts += IntLib.abs(option.amount) - amountCancelled;
            } else {
              nakedShorts += IntLib.abs(option2.amount) - amountCancelled;
            }
          } else if (option.amount < 0) {
            // both negative
            nakedShorts += IntLib.abs(option.amount) + IntLib.abs(option2.amount);
          }

          found = true;
        }
      }
      if (!found && option.amount < 0) {
        nakedShorts += IntLib.abs(option.amount);
      }
    }

    return nakedShorts.multiplyDecimal(otherContParams.optionPercent).multiplyDecimal(spotPrice);
  }
}
