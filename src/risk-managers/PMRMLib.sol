// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "openzeppelin/access/Ownable2Step.sol";
import {SafeCast} from "openzeppelin/utils/math/SafeCast.sol";
import {SignedMath} from "openzeppelin/utils/math/SignedMath.sol";
import {Math} from "openzeppelin/utils/math/Math.sol";
import "lyra-utils/math/Black76.sol";
import "lyra-utils/decimals/SignedDecimalMath.sol";
import "lyra-utils/decimals/DecimalMath.sol";

import {IPMRM} from "../interfaces/IPMRM.sol";
import {IPMRMLib} from "../interfaces/IPMRMLib.sol";

/**
 * @title PMRMLib
 * @notice Functions for helping compute PMRM value and risk (maintenance/initial margin and MTM)
 */
contract PMRMLib is IPMRMLib, Ownable2Step {
  using SignedDecimalMath for int;
  using DecimalMath for uint;
  using SafeCast for uint;
  using SafeCast for int;

  BasisContingencyParameters internal basisContParams;
  OtherContingencyParameters internal otherContParams;
  MarginParameters internal marginParams;
  VolShockParameters internal volShockParams;

  constructor() Ownable(msg.sender) {}

  ///////////
  // Admin //
  ///////////

  function setBasisContingencyParams(IPMRMLib.BasisContingencyParameters memory _basisContParams) external onlyOwner {
    if (
      _basisContParams.scenarioSpotUp <= 1e18 || _basisContParams.scenarioSpotUp > 3e18
        || _basisContParams.scenarioSpotDown >= 1e18 || _basisContParams.basisContMultFactor > 5e18
        || _basisContParams.basisContAddFactor > 5e18
    ) {
      revert PMRML_InvalidBasisContingencyParameters();
    }
    basisContParams = _basisContParams;
  }

  /// @dev Note: sufficiently large spot shock down and basePercent means adding base to the portfolio will always
  /// decrease MM -
  function setOtherContingencyParams(IPMRMLib.OtherContingencyParameters memory _otherContParams) external onlyOwner {
    if (
      _otherContParams.pegLossThreshold > 1e18 || _otherContParams.pegLossFactor > 20e18
        || _otherContParams.confThreshold > 1e18 || _otherContParams.confMargin > 1.5e18
        || _otherContParams.basePercent > 1e18 || _otherContParams.perpPercent > 1e18
        || _otherContParams.optionPercent > 1e18
    ) {
      revert PMRML_InvalidOtherContingencyParameters();
    }
    otherContParams = _otherContParams;
  }

  function setMarginParams(IPMRMLib.MarginParameters memory _marginParams) external onlyOwner {
    if (
      _marginParams.baseStaticDiscount > 1e18 || _marginParams.rateMultScale > 5e18 || _marginParams.rateAddScale > 5e18
        || _marginParams.imFactor < 1e18 || _marginParams.imFactor > 4e18
    ) {
      revert PMRML_InvalidMarginParameters();
    }
    marginParams = _marginParams;
  }

  function setVolShockParams(IPMRMLib.VolShockParameters memory _volShockParams) external onlyOwner {
    if (
      _volShockParams.volRangeUp > 2e18 //
        || _volShockParams.volRangeDown > 2e18 || _volShockParams.shortTermPower > 0.5e18
        || _volShockParams.longTermPower > 0.5e18 || _volShockParams.dteFloor > 100 days //
        || _volShockParams.dteFloor < 0.01 days // 864 seconds
    ) {
      revert PMRML_InvalidVolShockParameters();
    }
    volShockParams = _volShockParams;
  }

  //////////////////////
  // MTM calculations //
  //////////////////////

  /**
   * @return margin The margin result, either IM or MM depending on "isInitial"
   * @return markToMarket The mark-to-market value of the portfolio
   * @return worstScenario The index of the worst scenario, if == scenarios.length, it is the basis contingency
   */
  function getMarginAndMarkToMarket(IPMRM.Portfolio memory portfolio, bool isInitial, IPMRM.Scenario[] memory scenarios)
    external
    view
    returns (int margin, int markToMarket, uint worstScenario)
  {
    if (scenarios.length == 0) revert PMRML_InvalidGetMarginState();

    int minSPAN = portfolio.basisContingency;
    worstScenario = scenarios.length;

    for (uint i = 0; i < scenarios.length; ++i) {
      IPMRM.Scenario memory scenario = scenarios[i];

      // SPAN value with discounting applied, and only the difference from MtM
      int scenarioMTM = getScenarioMtM(portfolio, scenario);
      if (scenarioMTM < minSPAN) {
        minSPAN = scenarioMTM;
        worstScenario = i;
      }
    }

    minSPAN -= portfolio.staticContingency.toInt256();

    if (isInitial) {
      uint mFactor = marginParams.imFactor;
      if (portfolio.stablePrice < otherContParams.pegLossThreshold) {
        mFactor +=
          (otherContParams.pegLossThreshold - portfolio.stablePrice).multiplyDecimal(otherContParams.pegLossFactor);
      }

      minSPAN = minSPAN.multiplyDecimal(mFactor.toInt256());

      minSPAN -= portfolio.confidenceContingency.toInt256();
    }

    return (minSPAN + portfolio.totalMtM + portfolio.cash, portfolio.totalMtM + portfolio.cash, worstScenario);
  }

  function getScenarioMtM(IPMRM.Portfolio memory portfolio, IPMRM.Scenario memory scenario)
    public
    view
    returns (int scenarioMtM)
  {
    for (uint j = 0; j < portfolio.expiries.length; ++j) {
      IPMRM.ExpiryHoldings memory expiry = portfolio.expiries[j];

      int shockedExpiryMTM;
      // Check cached values
      if (scenario.volShock == IPMRM.VolShockDirection.None && scenario.spotShock == DecimalMath.UNIT) {
        // we've already calculated this previously, so just use that
        shockedExpiryMTM = expiry.mtm;
      } else if (
        scenario.volShock == IPMRM.VolShockDirection.None && scenario.spotShock == basisContParams.scenarioSpotUp
      ) {
        // NOTE: this value may not be cached depending on how _addPrecomputes was called; so be careful.
        shockedExpiryMTM = expiry.basisScenarioUpMtM;
      } else if (
        scenario.volShock == IPMRM.VolShockDirection.None && scenario.spotShock == basisContParams.scenarioSpotDown
      ) {
        // NOTE: this value may not be cached depending on how _addPrecomputes was called; so be careful.
        shockedExpiryMTM = expiry.basisScenarioDownMtM;
      } else {
        shockedExpiryMTM = _getExpiryShockedMTM(expiry, scenario.spotShock, scenario.volShock);
      }

      // we subtract expiry MtM as we only care about the difference from the current mtm at this stage
      scenarioMtM += _applyMTMDiscount(shockedExpiryMTM, expiry.staticDiscount) - expiry.mtm;
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
  ) internal pure returns (int mtm) {
    uint volShock = DecimalMath.UNIT;
    if (volShockDirection == IPMRM.VolShockDirection.Up) {
      volShock = expiry.volShockUp;
    } else if (volShockDirection == IPMRM.VolShockDirection.Down) {
      volShock = expiry.volShockDown;
    }

    uint64 secToExpiry = expiry.secToExpiry.toUint64();
    uint128 forwardPrice =
      (expiry.forwardVariablePortion.multiplyDecimal(spotShock) + expiry.forwardFixedPortion).toUint128();

    int totalMTM = 0;
    for (uint i = 0; i < expiry.options.length; i++) {
      IPMRM.StrikeHolding memory option = expiry.options[i];
      (uint call, uint put) = Black76.prices(
        Black76.Black76Inputs({
          timeToExpirySec: secToExpiry,
          volatility: option.vol.multiplyDecimal(volShock).toUint128(),
          fwdPrice: forwardPrice,
          strikePrice: option.strike.toUint128(),
          discount: 1e18
        })
      );

      totalMTM += (option.isCall ? call.toInt256() : put.toInt256()).multiplyDecimal(option.amount);
    }

    return totalMTM;
  }

  function _applyMTMDiscount(int shockedExpiryMTM, uint staticDiscount) internal pure returns (int) {
    if (shockedExpiryMTM > 0) {
      return shockedExpiryMTM.multiplyDecimal(staticDiscount.toInt256());
    } else {
      return shockedExpiryMTM;
    }
  }

  function _getShockedPerpValue(int position, uint perpPrice, uint spotShock) internal pure returns (int) {
    if (position == 0) {
      return 0;
    }
    int value = (spotShock.toInt256() - SignedDecimalMath.UNIT).multiplyDecimal(perpPrice.toInt256());
    return position.multiplyDecimal(value);
  }

  function _getBaseValue(uint position, uint spot, uint stablePrice, uint spotShock) internal pure returns (uint) {
    if (position == 0) {
      return 0;
    }
    return position.multiplyDecimal(spot).multiplyDecimal(spotShock).divideDecimal(stablePrice);
  }

  /////////////////
  // Precomputes //
  /////////////////

  // Precomputes are values used within SPAN for all shocks, so we only calculate them once
  function addPrecomputes(IPMRM.Portfolio memory portfolio) external view returns (IPMRM.Portfolio memory) {
    portfolio.baseValue =
      _getBaseValue(portfolio.basePosition, portfolio.spotPrice, portfolio.stablePrice, DecimalMath.UNIT);
    portfolio.totalMtM += portfolio.baseValue.toInt256();
    portfolio.totalMtM += portfolio.perpValue;

    uint basePerpContingencyFactor = SignedMath.abs(portfolio.perpPosition).multiplyDecimal(otherContParams.perpPercent);
    basePerpContingencyFactor += portfolio.basePosition.multiplyDecimal(otherContParams.basePercent);
    portfolio.staticContingency = basePerpContingencyFactor.multiplyDecimal(portfolio.spotPrice);

    portfolio.confidenceContingency = _getConfidenceContingency(
      portfolio.minConfidence, SignedMath.abs(portfolio.perpPosition) + portfolio.basePosition, portfolio.spotPrice
    );

    for (uint i = 0; i < portfolio.expiries.length; ++i) {
      IPMRM.ExpiryHoldings memory expiry = portfolio.expiries[i];

      expiry.minConfidence = Math.min(portfolio.minConfidence, expiry.minConfidence);

      // Current MtM and basis contingency MtMs
      expiry.mtm = _getExpiryShockedMTM(expiry, DecimalMath.UNIT, IPMRM.VolShockDirection.None);
      portfolio.totalMtM += expiry.mtm;

      _addBasisContingency(portfolio, expiry);

      _addVolShocks(expiry);
      _addStaticDiscount(expiry);

      portfolio.staticContingency += _getOptionContingency(expiry, portfolio.spotPrice);

      portfolio.confidenceContingency +=
        _getConfidenceContingency(expiry.minConfidence, expiry.netOptions, portfolio.spotPrice);
    }

    return portfolio;
  }

  function _addStaticDiscount(IPMRM.ExpiryHoldings memory expiry) internal view {
    uint tAnnualised = Black76.annualise(expiry.secToExpiry.toUint64());
    uint shockRFR = expiry.rate.multiplyDecimal(marginParams.rateMultScale) + marginParams.rateAddScale;
    expiry.staticDiscount = marginParams.baseStaticDiscount.multiplyDecimal(
      FixedPointMathLib.exp(-tAnnualised.multiplyDecimal(shockRFR).toInt256())
    );
  }

  function _addVolShocks(IPMRM.ExpiryHoldings memory expiry) internal view {
    int tau = (30 days * DecimalMath.UNIT / Math.max(expiry.secToExpiry, volShockParams.dteFloor)).toInt256();
    uint multShock = FixedPointMathLib.decPow(
      tau, expiry.secToExpiry <= 30 days ? volShockParams.shortTermPower : volShockParams.longTermPower
    );

    expiry.volShockUp = DecimalMath.UNIT + volShockParams.volRangeUp.multiplyDecimal(multShock);
    int volShockDown = SignedDecimalMath.UNIT - int(volShockParams.volRangeDown.multiplyDecimal(multShock));
    expiry.volShockDown = SignedMath.max(0, volShockDown).toUint256();
  }

  ///////////////////
  // Contingencies //
  ///////////////////

  function _addBasisContingency(IPMRM.Portfolio memory portfolio, IPMRM.ExpiryHoldings memory expiry) internal view {
    expiry.basisScenarioUpMtM =
      _getExpiryShockedMTM(expiry, basisContParams.scenarioSpotUp, IPMRM.VolShockDirection.None);
    expiry.basisScenarioDownMtM =
      _getExpiryShockedMTM(expiry, basisContParams.scenarioSpotDown, IPMRM.VolShockDirection.None);

    int basisContingency = SignedMath.min(
      SignedMath.min(expiry.basisScenarioUpMtM - expiry.mtm, expiry.basisScenarioDownMtM - expiry.mtm), 0
    );
    int basisContingencyFactor = int(
      basisContParams.basisContAddFactor //
        + basisContParams.basisContMultFactor.multiplyDecimal(Black76.annualise(expiry.secToExpiry.toUint64()))
    );
    portfolio.basisContingency += basisContingency.multiplyDecimal(basisContingencyFactor);
  }

  function _getConfidenceContingency(uint minConfidence, uint amtAffected, uint spotPrice) internal view returns (uint) {
    if (minConfidence < otherContParams.confThreshold) {
      return (DecimalMath.UNIT - minConfidence).multiplyDecimal(otherContParams.confMargin).multiplyDecimal(amtAffected)
        .multiplyDecimal(spotPrice);
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

  //////////
  // View //
  //////////

  function getBasisContingencyParams() external view returns (IPMRMLib.BasisContingencyParameters memory) {
    return basisContParams;
  }

  function getVolShockParams() external view returns (IPMRMLib.VolShockParameters memory) {
    return volShockParams;
  }

  function getStaticDiscountParams() external view returns (IPMRMLib.MarginParameters memory) {
    return marginParams;
  }

  function getOtherContingencyParams() external view returns (IPMRMLib.OtherContingencyParameters memory) {
    return otherContParams;
  }

  function getBasisContingencyScenarios() external view returns (IPMRM.Scenario[] memory scenarios) {
    scenarios = new IPMRM.Scenario[](3);
    scenarios[0] = IPMRM.Scenario({spotShock: basisContParams.scenarioSpotUp, volShock: IPMRM.VolShockDirection.None});
    scenarios[1] = IPMRM.Scenario({spotShock: basisContParams.scenarioSpotDown, volShock: IPMRM.VolShockDirection.None});
    scenarios[2] = IPMRM.Scenario({spotShock: DecimalMath.UNIT, volShock: IPMRM.VolShockDirection.None});
  }
}
