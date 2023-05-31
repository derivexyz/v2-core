// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "openzeppelin/access/Ownable2Step.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/math/SignedMath.sol";
import "openzeppelin/utils/math/Math.sol";
import "lyra-utils/math/Black76.sol";
import "lyra-utils/decimals/SignedDecimalMath.sol";
import "lyra-utils/decimals/DecimalMath.sol";

import "src/interfaces/IOptionPricing.sol";
import "src/interfaces/IPMRM.sol";
import "src/interfaces/IPMRMLib.sol";
import "src/interfaces/ISubAccounts.sol";

import "forge-std/console2.sol";

contract PMRMLib is IPMRMLib, Ownable2Step {
  using SignedDecimalMath for int;
  using DecimalMath for uint;
  using SafeCast for uint;
  using SafeCast for int;

  /// @dev Pricing module to get option mark-to-market price
  IOptionPricing public optionPricing;

  ForwardContingencyParameters fwdContParams;
  OtherContingencyParameters otherContParams;
  StaticDiscountParameters staticDiscountParams;
  VolShockParameters volShockParams;

  constructor(IOptionPricing _optionPricing) Ownable2Step() {
    optionPricing = _optionPricing;
  }

  ///////////
  // Admin //
  ///////////

  function setOptionPricing(IOptionPricing _optionPricing) external onlyOwner {
    optionPricing = _optionPricing;
  }

  function setForwardContingencyParams(IPMRMLib.ForwardContingencyParameters memory _fwdContParams) external onlyOwner {
    if (
      _fwdContParams.spotShock1 >= 1e18 || _fwdContParams.spotShock2 <= 1e18
        || _fwdContParams.multiplicativeFactor > 1e18
    ) {
      revert PMRML_InvalidForwardContingencyParameters();
    }
    fwdContParams = _fwdContParams;
  }

  function setOtherContingencyParams(IPMRMLib.OtherContingencyParameters memory _otherContParams) external onlyOwner {
    if (
      _otherContParams.pegLossThreshold >= 1e18 || _otherContParams.confidenceThreshold >= 1e18
        || _otherContParams.confidenceFactor > 2e18 || _otherContParams.basePercent > 1e18
        || _otherContParams.perpPercent > 1e18 || _otherContParams.optionPercent > 1e18
    ) {
      revert PMRML_InvalidOtherContingencyParameters();
    }
    otherContParams = _otherContParams;
  }

  function setStaticDiscountParams(IPMRMLib.StaticDiscountParameters memory _staticDiscountParams) external onlyOwner {
    if (
      _staticDiscountParams.baseStaticDiscount >= 1e18 || _staticDiscountParams.rateMultiplicativeFactor > 10e18
        || _staticDiscountParams.rateAdditiveFactor > 1e18
    ) {
      revert PMRML_InvalidStaticDiscountParameters();
    }
    staticDiscountParams = _staticDiscountParams;
  }

  function setVolShockParams(IPMRMLib.VolShockParameters memory _volShockParams) external onlyOwner {
    // TODO: more bounds (for this and the above)
    if (_volShockParams.dteFloor > 10 days) {
      revert PMRML_InvalidVolShockParameters();
    }
    volShockParams = _volShockParams;
  }

  //////////////////////
  // MTM calculations //
  //////////////////////

  function _getMarginAndMarkToMarket(
    IPMRM.Portfolio memory portfolio,
    bool isInitial,
    IPMRM.Scenario[] memory scenarios,
    bool useFwdContingency
  ) internal view returns (int margin, int markToMarket) {
    int minSPAN = useFwdContingency ? portfolio.fwdContingency : type(int).max;

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
      uint mFactor = 1.3e18;
      if (portfolio.stablePrice < otherContParams.pegLossThreshold) {
        mFactor +=
          (otherContParams.pegLossThreshold - portfolio.stablePrice).multiplyDecimal(otherContParams.pegLossFactor);
      }

      minSPAN = minSPAN.multiplyDecimal(mFactor.toInt256());

      minSPAN -= portfolio.confidenceContingency.toInt256();
    }

    return (minSPAN + portfolio.totalMtM + portfolio.cash, portfolio.totalMtM + portfolio.cash);
  }

  function getScenarioMtM(IPMRM.Portfolio memory portfolio, IPMRM.Scenario memory scenario)
    internal
    view
    returns (int scenarioMtM)
  {
    for (uint j = 0; j < portfolio.expiries.length; ++j) {
      IPMRM.ExpiryHoldings memory expiry = portfolio.expiries[j];

      int expiryMtM;
      // Check cached values
      if (scenario.volShock == IPMRM.VolShockDirection.None && scenario.spotShock == DecimalMath.UNIT) {
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
      // TODO: do we use static discount the same for MM? seems a bit punishing
      scenarioMtM += _applyMTMDiscount(expiryMtM, expiry.staticDiscount) - expiry.mtm;
    }

    uint shockedBaseValue =
      _getBaseValue(portfolio.basePosition, portfolio.spotPrice, portfolio.stablePrice, scenario.spotShock);
    int shockedPerpValue = _getShockedPerpValue(portfolio.perpPosition, portfolio.perpPrice, scenario.spotShock);

    scenarioMtM += (shockedBaseValue.toInt256() + shockedPerpValue - portfolio.baseValue.toInt256());
  }

  // calculate MTM with given shock
  function _getExpiryShockedMTM(
    IPMRM.ExpiryHoldings memory expiry,
    uint spotShock,
    IPMRM.VolShockDirection volShockDirection
  ) internal view returns (int mtm) {
    uint volShock = DecimalMath.UNIT;
    if (volShockDirection == IPMRM.VolShockDirection.Up) {
      volShock = expiry.volShockUp;
    } else if (volShockDirection == IPMRM.VolShockDirection.Down) {
      volShock = expiry.volShockDown;
    }

    // TODO: maybe these structs should be precomputed? Test gas
    IOptionPricing.Expiry memory expiryDetails = IOptionPricing.Expiry({
      secToExpiry: expiry.secToExpiry.toUint64(),
      forwardPrice: (expiry.forwardVariablePortion.multiplyDecimal(spotShock) + expiry.forwardFixedPortion).toUint128(),
      discountFactor: DecimalMath.UNIT.toUint64()
    });

    IOptionPricing.Option[] memory optionDetails = new IOptionPricing.Option[](expiry.options.length);
    for (uint i = 0; i < expiry.options.length; i++) {
      IPMRM.StrikeHolding memory option = expiry.options[i];
      optionDetails[i] = IOptionPricing.Option({
        strike: option.strike.toUint128(),
        vol: option.vol.multiplyDecimal(volShock).toUint128(),
        amount: option.amount,
        isCall: option.isCall
      });
    }

    return optionPricing.getExpiryOptionsValue(expiryDetails, optionDetails);
  }

  function _applyMTMDiscount(int expiryMTM, uint staticDiscount) internal pure returns (int) {
    if (expiryMTM > 0) {
      // TODO: just store staticDiscount as int
      return expiryMTM.multiplyDecimal(staticDiscount.toInt256());
    } else {
      return expiryMTM;
    }
  }

  function _getShockedPerpValue(int position, uint spotPrice, uint spotShock) internal pure returns (int) {
    int value = (spotShock.toInt256() - SignedDecimalMath.UNIT).multiplyDecimal(spotPrice.toInt256());
    return position.multiplyDecimal(value);
  }

  function _getBaseValue(uint position, uint spot, uint stablePrice, uint spotShock) internal pure returns (uint) {
    return position.multiplyDecimal(spot).multiplyDecimal(spotShock).divideDecimal(stablePrice);
  }

  /////////////////
  // Precomputes //
  /////////////////

  // Precomputes are values used within SPAN for all shocks, so we only calculate them once
  function _addPrecomputes(IPMRM.Portfolio memory portfolio, bool addForwardCont) internal view {
    portfolio.baseValue =
      _getBaseValue(portfolio.basePosition, portfolio.spotPrice, portfolio.stablePrice, DecimalMath.UNIT);
    portfolio.totalMtM += SafeCast.toInt256(portfolio.baseValue);
    portfolio.totalMtM += portfolio.perpValue;

    uint basePerpContingencyFactor = SignedMath.abs(portfolio.perpPosition).multiplyDecimal(otherContParams.perpPercent);
    basePerpContingencyFactor += portfolio.basePosition.multiplyDecimal(otherContParams.basePercent);
    portfolio.staticContingency = basePerpContingencyFactor.multiplyDecimal(portfolio.spotPrice);

    portfolio.confidenceContingency = _getConfidenceContingency(
      portfolio.minConfidence, SignedMath.abs(portfolio.perpPosition) + portfolio.basePosition, portfolio.spotPrice
    );

    for (uint i = 0; i < portfolio.expiries.length; ++i) {
      IPMRM.ExpiryHoldings memory expiry = portfolio.expiries[i];

      // Current MtM and forward contingency MtMs
      expiry.mtm = _getExpiryShockedMTM(expiry, DecimalMath.UNIT, IPMRM.VolShockDirection.None);
      portfolio.totalMtM += expiry.mtm;

      if (addForwardCont) {
        _addForwardContingency(portfolio, expiry);
      }

      _addVolShocks(expiry);
      _addStaticDiscount(expiry);

      portfolio.staticContingency += _getOptionContingency(expiry, portfolio.spotPrice);

      portfolio.confidenceContingency +=
        _getConfidenceContingency(expiry.minConfidence, expiry.netOptions, portfolio.spotPrice);
    }
  }

  function _addStaticDiscount(IPMRM.ExpiryHoldings memory expiry) internal view {
    uint tAnnualised = expiry.secToExpiry * DecimalMath.UNIT / 365 days;
    uint cappedRate = expiry.rate < 0 ? 0 : uint(int(expiry.rate));
    uint shockRFR = cappedRate.multiplyDecimal(staticDiscountParams.rateMultiplicativeFactor)
      + staticDiscountParams.rateAdditiveFactor;
    expiry.staticDiscount = staticDiscountParams.baseStaticDiscount.multiplyDecimal(
      FixedPointMathLib.exp(-tAnnualised.multiplyDecimal(shockRFR).toInt256())
    );
  }

  function _addVolShocks(IPMRM.ExpiryHoldings memory expiry) internal view {
    int tao = (30 days * DecimalMath.UNIT / Math.max(expiry.secToExpiry, volShockParams.dteFloor)).toInt256();
    uint multShock = FixedPointMathLib.decPow(
      tao, expiry.secToExpiry <= 30 days ? volShockParams.shortTermPower : volShockParams.longTermPower
    );

    expiry.volShockUp = DecimalMath.UNIT + volShockParams.volRangeUp.multiplyDecimal(multShock);
    expiry.volShockDown =
      SafeCast.toUint256(SignedDecimalMath.UNIT - int(volShockParams.volRangeDown.multiplyDecimal(multShock)));
  }

  ///////////////////
  // Contingencies //
  ///////////////////

  function _addForwardContingency(IPMRM.Portfolio memory portfolio, IPMRM.ExpiryHoldings memory expiry) internal view {
    expiry.fwdShock1MtM = _getExpiryShockedMTM(expiry, fwdContParams.spotShock1, IPMRM.VolShockDirection.None);
    expiry.fwdShock2MtM = _getExpiryShockedMTM(expiry, fwdContParams.spotShock2, IPMRM.VolShockDirection.None);

    int fwdContingency =
      SignedMath.min(SignedMath.min(expiry.fwdShock1MtM - expiry.mtm, expiry.fwdShock2MtM - expiry.mtm), 0);
    int fwdContingencyFactor = int(
      fwdContParams.additiveFactor //
        + fwdContParams.multiplicativeFactor.multiplyDecimal(Black76.annualise(uint64(expiry.secToExpiry)))
    );
    portfolio.fwdContingency += fwdContingency.multiplyDecimal(fwdContingencyFactor);
  }

  function _getConfidenceContingency(uint minConfidence, uint amtAffected, uint spotPrice) internal view returns (uint) {
    if (minConfidence < otherContParams.confidenceThreshold) {
      return (DecimalMath.UNIT - minConfidence).multiplyDecimal(otherContParams.confidenceFactor).multiplyDecimal(
        amtAffected
      ).multiplyDecimal(spotPrice);
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
            if (option.amount < 0) {
              nakedShorts += SignedMath.abs(option.amount) - SignedMath.min(-option.amount, option2.amount).toUint256();
            } else {
              nakedShorts += SignedMath.abs(option2.amount) - SignedMath.min(option.amount, -option2.amount).toUint256();
            }
          } else if (option.amount < 0) {
            // both negative
            nakedShorts += SignedMath.abs(option.amount) + SignedMath.abs(option2.amount);
          }

          found = true;
        }
      }
      if (!found && option.amount < 0) {
        nakedShorts += SignedMath.abs(option.amount);
      }
    }

    return nakedShorts.multiplyDecimal(otherContParams.optionPercent).multiplyDecimal(spotPrice);
  }

  ////
  // View

  function getForwardContingencyParams() external view returns (IPMRMLib.ForwardContingencyParameters memory) {
    return fwdContParams;
  }

  function getVolShockParams() external view returns (IPMRMLib.VolShockParameters memory) {
    return volShockParams;
  }

  function getStaticDiscountParams() external view returns (IPMRMLib.StaticDiscountParameters memory) {
    return staticDiscountParams;
  }

  function getOtherContingencyParams() external view returns (IPMRMLib.OtherContingencyParameters memory) {
    return otherContParams;
  }
}
