// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "lyra-utils/decimals/DecimalMath.sol";
import "lyra-utils/decimals/SignedDecimalMath.sol";
import "lyra-utils/math/Black76.sol";
import {IPMRMLib_2} from "../interfaces/IPMRMLib_2.sol";
import {IPMRM_2} from "../interfaces/IPMRM_2.sol";
import {ISpotFeed} from "../interfaces/ISpotFeed.sol";

import {Math} from "openzeppelin/utils/math/Math.sol";
import "openzeppelin/access/Ownable2Step.sol";
import {SafeCast} from "openzeppelin/utils/math/SafeCast.sol";
import {SignedMath} from "openzeppelin/utils/math/SignedMath.sol";
import {WrappedERC20Asset} from "../assets/WrappedERC20Asset.sol";
import {PMRM_2} from "./PMRM_2.sol";

/**
 * @title PMRMLib
 * @notice Functions for helping compute PMRM value and risk (maintenance/initial margin and MTM)
 */
contract PMRMLib_2 is IPMRMLib_2, Ownable2Step {
  using SignedDecimalMath for int;
  using DecimalMath for uint;
  using SafeCast for uint;
  using SafeCast for int;

  BasisContingencyParameters internal basisContParams;
  OtherContingencyParameters internal otherContParams;
  MarginParameters internal marginParams;
  VolShockParameters internal volShockParams;
  SkewShockParameters internal skewShockParams;
  mapping(address => CollateralParameters) public collaterals;

  constructor() Ownable(msg.sender) {}

  ///////////
  // Admin //
  ///////////

  function setBasisContingencyParams(IPMRMLib_2.BasisContingencyParameters memory _basisContParams) external onlyOwner {
    require(
      _basisContParams.scenarioSpotUp > 1e18 && _basisContParams.scenarioSpotUp < 3e18
        && _basisContParams.scenarioSpotDown < 1e18 && _basisContParams.basisContMultFactor <= 20e18
        && _basisContParams.basisContAddFactor <= 20e18,
      PMRML2_InvalidBasisContingencyParameters()
    );

    basisContParams = _basisContParams;
    emit BasisContingencyParamsUpdated(_basisContParams);
  }

  /// @dev Note: sufficiently large spot shock down and basePercent means adding base to the portfolio will always
  /// decrease MM -
  function setOtherContingencyParams(IPMRMLib_2.OtherContingencyParameters memory _otherContParams) external onlyOwner {
    require(
      _otherContParams.pegLossThreshold <= 100e18 && _otherContParams.pegLossFactor <= 10e18
        && _otherContParams.confThreshold <= 1e18 && _otherContParams.confMargin <= 20e18
        && _otherContParams.MMPerpPercent <= 3e18 && _otherContParams.IMPerpPercent <= 3e18
        && _otherContParams.MMOptionPercent <= 2e18 && _otherContParams.IMOptionPercent <= 2e18,
      PMRML2_InvalidOtherContingencyParameters()
    );

    otherContParams = _otherContParams;
    emit OtherContingencyParamsUpdated(_otherContParams);
  }

  function setMarginParams(IPMRMLib_2.MarginParameters memory _marginParams) external onlyOwner {
    require(
      _marginParams.imFactor >= 0.5e18 && _marginParams.imFactor <= 10e18 && _marginParams.mmFactor >= 0.1e18
        && _marginParams.mmFactor <= 10e18 && _marginParams.shortRateMultScale <= 10e18
        && _marginParams.longRateMultScale <= 10e18 && _marginParams.shortRateAddScale <= 10e18
        && _marginParams.longRateAddScale <= 10e18 && _marginParams.shortBaseStaticDiscount <= 4e18
        && _marginParams.longBaseStaticDiscount <= 4e18,
      PMRML2_InvalidMarginParameters()
    );

    marginParams = _marginParams;
    emit MarginParamsUpdated(_marginParams);
  }

  function setVolShockParams(IPMRMLib_2.VolShockParameters memory _volShockParams) external onlyOwner {
    require(
      _volShockParams.volRangeUp <= 10e18 && _volShockParams.volRangeDown <= 10e18
        && _volShockParams.shortTermPower <= 10e18 && _volShockParams.longTermPower <= 10e18
        && _volShockParams.dteFloor <= 400 days && _volShockParams.minVolUpShock <= 20e18,
      PMRML2_InvalidVolShockParameters()
    );
    volShockParams = _volShockParams;
    emit VolShockParamsUpdated(_volShockParams);
  }

  function setSkewShockParameters(SkewShockParameters memory _skewShockParams) external onlyOwner {
    require(
      _skewShockParams.linearBaseCap <= 10e18 && _skewShockParams.absBaseCap <= 10e18
        && _skewShockParams.linearCBase >= -10e18 && _skewShockParams.linearCBase <= 10e18
        && _skewShockParams.absCBase >= -10e18 && _skewShockParams.absCBase <= 10e18 && _skewShockParams.minKStar >= 0
        && _skewShockParams.minKStar <= 10e18 && _skewShockParams.widthScale >= 0 && _skewShockParams.widthScale <= 10e18
        && _skewShockParams.volParamStatic >= 0 && _skewShockParams.volParamStatic <= 10e18
        && _skewShockParams.volParamScale >= -20e18 && _skewShockParams.volParamScale <= 20e18,
      PMRML2_InvalidSkewShockParameters()
    );
    skewShockParams = _skewShockParams;
    emit SkewShockParamsUpdated(_skewShockParams);
  }

  function setCollateralParameters(address asset, CollateralParameters memory params) external onlyOwner {
    // once enabled cannot be disabled, must have haircuts set to 100% instead. Otherwise subaccounts may be frozen
    require(
      params.isEnabled && (params.IMHaircut + params.MMHaircut) <= 1e18 && params.MMHaircut <= 1e18,
      PMRML2_InvalidCollateralParameters()
    );
    // Note: asset must be added to pmrm to be used as collateral. If
    collaterals[asset] = params;
    emit CollateralParametersUpdated(asset, params);
  }

  //////////////////////
  // MTM calculations //
  //////////////////////

  /**
   * @return margin The margin result, either IM or MM depending on "isInitial"
   * @return markToMarket The mark-to-market value of the portfolio
   * @return worstScenario The index of the worst scenario, if == scenarios.length, it is the basis contingency
   */
  function getMarginAndMarkToMarket(
    IPMRM_2.Portfolio memory portfolio,
    bool isInitial,
    IPMRM_2.Scenario[] memory scenarios
  ) external view returns (int margin, int markToMarket, uint worstScenario) {
    require(scenarios.length > 0, PMRML2_InvalidGetMarginState());

    int minSPAN = portfolio.basisContingency;
    worstScenario = scenarios.length;

    for (uint i = 0; i < scenarios.length; ++i) {
      IPMRM_2.Scenario memory scenario = scenarios[i];

      // SPAN value with discounting applied, and only the *difference from MtM*
      int scenarioPnL = getScenarioPnL(portfolio, scenario);
      if (scenarioPnL < minSPAN) {
        minSPAN = scenarioPnL;
        worstScenario = i;
      }
    }

    uint mFactor = isInitial ? marginParams.imFactor : marginParams.mmFactor;

    // peg loss factor
    if (isInitial && portfolio.stablePrice < otherContParams.pegLossThreshold) {
      uint pegLoss = otherContParams.pegLossThreshold - portfolio.stablePrice;
      mFactor += pegLoss.multiplyDecimal(otherContParams.pegLossFactor);
    }

    minSPAN = minSPAN.multiplyDecimal(mFactor.toInt256());

    if (isInitial) {
      minSPAN -= portfolio.IMContingency.toInt256();
    }
    minSPAN -= portfolio.MMContingency.toInt256();

    return (minSPAN + portfolio.totalMtM + portfolio.cash, portfolio.totalMtM + portfolio.cash, worstScenario);
  }

  // @dev Calculates the DIFFERENCE to the atm MTM
  function getScenarioPnL(IPMRM_2.Portfolio memory portfolio, IPMRM_2.Scenario memory scenario)
    public
    view
    returns (int scenarioPnL)
  {
    // Perp - we ignore mark value it is unaffected by any shock, and we only care about the difference to mtm
    scenarioPnL += _getShockedPerpPnL(portfolio.perpPosition, portfolio.perpPrice, scenario.spotShock).multiplyDecimal(
      scenario.dampeningFactor.toInt256()
    );

    // Option
    for (uint j = 0; j < portfolio.expiries.length; ++j) {
      IPMRM_2.ExpiryHoldings memory expiry = portfolio.expiries[j];

      int shockedExpiryMTM;
      // Check cached values
      if (scenario.volShock == IPMRM_2.VolShockDirection.None && scenario.spotShock == DecimalMath.UNIT) {
        // we've already calculated this previously, so just use that
        shockedExpiryMTM = expiry.mtm;
      } else if (
        scenario.volShock == IPMRM_2.VolShockDirection.None && scenario.spotShock == basisContParams.scenarioSpotUp
      ) {
        // NOTE: this value may not be cached depending on how _addPrecomputes was called; so be careful.
        shockedExpiryMTM = expiry.basisScenarioUpMtM;
      } else if (
        scenario.volShock == IPMRM_2.VolShockDirection.None && scenario.spotShock == basisContParams.scenarioSpotDown
      ) {
        // NOTE: this value may not be cached depending on how _addPrecomputes was called; so be careful.
        shockedExpiryMTM = expiry.basisScenarioDownMtM;
      } else if (
        scenario.volShock == IPMRM_2.VolShockDirection.Linear || scenario.volShock == IPMRM_2.VolShockDirection.Abs
      ) {
        shockedExpiryMTM = _getExpirySkewedShockedMTM(expiry, scenario.volShock);
      } else {
        // Vol shock is either Up, Down, None
        shockedExpiryMTM = _getExpiryShockedMTM(expiry, scenario.spotShock, scenario.volShock);
      }

      shockedExpiryMTM = shockedExpiryMTM.multiplyDecimal(
        shockedExpiryMTM >= 0 ? expiry.staticDiscountPos.toInt256() : expiry.staticDiscountNeg.toInt256()
      );

      int expiryPnL = (shockedExpiryMTM - expiry.mtm).multiplyDecimal(scenario.dampeningFactor.toInt256());

      // To maximise loss we work out the worst case pnl for each expiry in skew scenarios. Inverting positive values
      // gives an approximation of rotating the vol skew in the opposite direction.
      if (scenario.volShock == IPMRM_2.VolShockDirection.Linear || scenario.volShock == IPMRM_2.VolShockDirection.Abs) {
        // for skew scenarios we use *negative* absolute value to maximise the loss for each expiry.
        scenarioPnL += expiryPnL > 0 ? -expiryPnL : expiryPnL;
      } else {
        scenarioPnL += expiryPnL;
      }
    }

    // Collateral
    for (uint j = 0; j < portfolio.collaterals.length; ++j) {
      IPMRM_2.CollateralHoldings memory collateral = portfolio.collaterals[j];
      // We only care about the difference to mtm, so we ignore those that are not risk cancelling
      if (!collaterals[address(collateral.asset)].isRiskCancelling) {
        continue;
      }

      // Otherwise, we calculate the difference to the mtm, by shocking the cached value by the spot shock (i.e. -0.2)
      scenarioPnL += collateral.value.toInt256().multiplyDecimal(scenario.spotShock.toInt256() - 1e18).multiplyDecimal(
        scenario.dampeningFactor.toInt256()
      );
    }

    return scenarioPnL;
  }

  // calculate MTM with given shock
  function _getExpiryShockedMTM(
    IPMRM_2.ExpiryHoldings memory expiry,
    uint spotShock,
    IPMRM_2.VolShockDirection volShockDirection
  ) internal view returns (int mtm) {
    uint volShock = DecimalMath.UNIT;
    uint minVol = 0;
    if (volShockDirection == IPMRM_2.VolShockDirection.Up) {
      volShock = expiry.volShockUp;
      minVol = volShockParams.minVolUpShock;
    } else if (volShockDirection == IPMRM_2.VolShockDirection.Down) {
      volShock = expiry.volShockDown;
    }

    uint64 secToExpiry = expiry.secToExpiry.toUint64();
    uint128 forwardPrice =
      (expiry.forwardVariablePortion.multiplyDecimal(spotShock) + expiry.forwardFixedPortion).toUint128();

    int totalMTM = 0;
    for (uint i = 0; i < expiry.options.length; i++) {
      IPMRM_2.StrikeHolding memory option = expiry.options[i];
      uint vol = Math.max(minVol, option.vol.multiplyDecimal(volShock));
      Black76.Black76Inputs memory bsInput = Black76.Black76Inputs({
        timeToExpirySec: secToExpiry,
        volatility: vol.toUint128(),
        fwdPrice: forwardPrice,
        strikePrice: option.strike.toUint128(),
        discount: expiry.discount
      });
      (uint call, uint put) = Black76.prices(bsInput);

      totalMTM += (option.isCall ? call.toInt256() : put.toInt256()).multiplyDecimal(option.amount);
    }

    return totalMTM;
  }

  /// @dev kstar is an estimate of where the vol surface flattens out and, hence, the approximate point where we cap
  /// the vol multiplier
  function _getKStar(int sqrtTau) internal view returns (int) {
    int volParam = skewShockParams.volParamStatic + sqrtTau.multiplyDecimal(skewShockParams.volParamScale);
    int kStar = sqrtTau.multiplyDecimal(skewShockParams.widthScale).multiplyDecimal(volParam);
    return SignedMath.max(skewShockParams.minKStar, kStar);
  }

  /// @dev calculate MTM with given skew shock, where the "wings" of the vol surface are raised/reduced
  function _getExpirySkewedShockedMTM(IPMRM_2.ExpiryHoldings memory expiry, IPMRM_2.VolShockDirection volShockDirection)
    internal
    view
    returns (int mtm)
  {
    // either linear or abs
    bool isLinear = volShockDirection == IPMRM_2.VolShockDirection.Linear;

    uint64 secToExpiry = expiry.secToExpiry.toUint64();
    uint128 forwardPrice = (expiry.forwardVariablePortion + expiry.forwardFixedPortion).toUint128();

    int sqrtTau = FixedPointMathLib.sqrt(Black76.annualise(secToExpiry)).toInt256();

    int multCap = isLinear //
      ? skewShockParams.linearCBase.multiplyDecimal(sqrtTau) + skewShockParams.linearBaseCap.toInt256()
      : skewShockParams.absCBase.multiplyDecimal(sqrtTau) + skewShockParams.absBaseCap.toInt256();

    int kStar = _getKStar(sqrtTau);

    int totalMTM = 0;
    for (uint i = 0; i < expiry.options.length; i++) {
      IPMRM_2.StrikeHolding memory option = expiry.options[i];

      Black76.Black76Inputs memory inputs = Black76.Black76Inputs({
        timeToExpirySec: secToExpiry,
        volatility: 0,
        fwdPrice: forwardPrice,
        strikePrice: option.strike.toUint128(),
        discount: expiry.discount
      });

      int k = FixedPointMathLib.ln(option.strike.divideDecimal(uint(forwardPrice)).toInt256());
      k = isLinear ? k : int(SignedMath.abs(k));

      int skewMultiplier = SignedDecimalMath.UNIT;
      if (k >= 0) {
        skewMultiplier += SignedMath.min(multCap, k * multCap / kStar);
      } else {
        skewMultiplier += SignedMath.max(-multCap, k * multCap / kStar);
      }

      inputs.volatility = option.vol.multiplyDecimal(skewMultiplier < 0 ? 0 : skewMultiplier.toUint256()).toUint128();

      (uint call, uint put) = Black76.prices(inputs);

      totalMTM += (option.isCall ? call.toInt256() : put.toInt256()).multiplyDecimal(option.amount);
    }

    return totalMTM;
  }

  function _getShockedPerpPnL(int position, uint perpPrice, uint spotShock) internal pure returns (int) {
    if (position == 0) {
      return 0;
    }
    int value = (spotShock.toInt256() - SignedDecimalMath.UNIT).multiplyDecimal(perpPrice.toInt256());
    return position.multiplyDecimal(value);
  }

  /////////////////
  // Precomputes //
  /////////////////

  // Precomputes are values used within SPAN for all shocks, so we only calculate them once
  function addPrecomputes(IPMRM_2.Portfolio memory portfolio) external view returns (IPMRM_2.Portfolio memory) {
    portfolio.totalMtM += portfolio.perpValue;

    uint perpNotional = SignedMath.abs(portfolio.perpPosition).multiplyDecimal(portfolio.spotPrice);

    portfolio.MMContingency = perpNotional.multiplyDecimal(otherContParams.MMPerpPercent);
    portfolio.IMContingency = perpNotional.multiplyDecimal(otherContParams.IMPerpPercent);
    portfolio.IMContingency += _getConfidenceContingency(portfolio.minConfidence, perpNotional);

    for (uint i = 0; i < portfolio.expiries.length; ++i) {
      IPMRM_2.ExpiryHoldings memory expiry = portfolio.expiries[i];

      expiry.minConfidence = Math.min(portfolio.minConfidence, expiry.minConfidence);

      // Current MtM and basis contingency MtMs
      expiry.mtm = _getExpiryShockedMTM(expiry, DecimalMath.UNIT, IPMRM_2.VolShockDirection.None);
      portfolio.totalMtM += expiry.mtm;

      _addBasisContingency(portfolio, expiry);

      _addVolShocks(expiry);
      _addStaticDiscount(expiry);
      _addOptionContingency(portfolio, expiry, portfolio.spotPrice);

      portfolio.IMContingency +=
        _getConfidenceContingency(expiry.minConfidence, expiry.netOptions.multiplyDecimal(portfolio.spotPrice));
    }

    for (uint i = 0; i < portfolio.collaterals.length; ++i) {
      IPMRM_2.CollateralHoldings memory collateral = portfolio.collaterals[i];
      CollateralParameters memory params = collaterals[address(collateral.asset)];

      require(params.isEnabled, PMRML2_CollateralDisabled());

      portfolio.totalMtM += collateral.value.toInt256();

      portfolio.MMContingency += collateral.value.multiplyDecimal(params.MMHaircut);
      portfolio.IMContingency += collateral.value.multiplyDecimal(params.IMHaircut);
      portfolio.IMContingency += _getConfidenceContingency(collateral.minConfidence, collateral.value);
    }

    return portfolio;
  }

  /// @dev Calculates the static discount for the expiry. This is a discount applied to the MtM of the expiry to dampen
  /// the time-value of the option value.
  function _addStaticDiscount(IPMRM_2.ExpiryHoldings memory expiry) internal view {
    // Note this is expected to revert if the rate is too high. Static discount will grow exponentially, causing shorts
    // to be massively discounted (requiring more margin)
    uint tau = Black76.annualise(expiry.secToExpiry.toUint64());

    uint shockRfrPos = expiry.rate.multiplyDecimal(marginParams.longRateMultScale) + marginParams.longRateAddScale;
    expiry.staticDiscountPos = marginParams.longBaseStaticDiscount.multiplyDecimal(
      FixedPointMathLib.exp(-(tau.multiplyDecimal(shockRfrPos).toInt256()))
    );

    uint shockRfrNeg = expiry.rate.multiplyDecimal(marginParams.shortRateMultScale) + marginParams.shortRateAddScale;
    expiry.staticDiscountNeg = marginParams.shortBaseStaticDiscount.divideDecimal(
      FixedPointMathLib.exp(-(tau.multiplyDecimal(shockRfrNeg).toInt256()))
    );

    expiry.staticDiscountNeg = Math.min(DecimalMath.UNIT.divideDecimal(uint(expiry.discount)), expiry.staticDiscountNeg);
  }

  function _addVolShocks(IPMRM_2.ExpiryHoldings memory expiry) internal view {
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

  function _addBasisContingency(IPMRM_2.Portfolio memory portfolio, IPMRM_2.ExpiryHoldings memory expiry) internal view {
    expiry.basisScenarioUpMtM =
      _getExpiryShockedMTM(expiry, basisContParams.scenarioSpotUp, IPMRM_2.VolShockDirection.None);
    expiry.basisScenarioDownMtM =
      _getExpiryShockedMTM(expiry, basisContParams.scenarioSpotDown, IPMRM_2.VolShockDirection.None);

    int basisContingency = SignedMath.min(
      SignedMath.min(expiry.basisScenarioUpMtM - expiry.mtm, expiry.basisScenarioDownMtM - expiry.mtm), 0
    );
    int basisContingencyFactor = int(
      basisContParams.basisContAddFactor //
        + basisContParams.basisContMultFactor.multiplyDecimal(Black76.annualise(expiry.secToExpiry.toUint64()))
    );
    portfolio.basisContingency += basisContingency.multiplyDecimal(basisContingencyFactor);
  }

  function _getConfidenceContingency(uint minConfidence, uint notionalAmt) internal view returns (uint) {
    if (minConfidence < otherContParams.confThreshold) {
      return (DecimalMath.UNIT - minConfidence).multiplyDecimal(otherContParams.confMargin).multiplyDecimal(notionalAmt);
    }
    return 0;
  }

  function _addOptionContingency(
    IPMRM_2.Portfolio memory portfolio,
    IPMRM_2.ExpiryHoldings memory expiry,
    uint spotPrice
  ) internal view {
    uint nakedShorts = 0;
    uint optionsLen = expiry.options.length;
    for (uint i = 0; i < optionsLen; ++i) {
      IPMRM_2.StrikeHolding memory option = expiry.options[i];
      if (option.seenInFilter) {
        continue;
      }
      bool found = false;

      for (uint j = i + 1; j < optionsLen; ++j) {
        IPMRM_2.StrikeHolding memory option2 = expiry.options[j];

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

    uint notionalShorts = nakedShorts.multiplyDecimal(spotPrice);

    portfolio.MMContingency += notionalShorts.multiplyDecimal(otherContParams.MMOptionPercent);
    portfolio.IMContingency += notionalShorts.multiplyDecimal(otherContParams.IMOptionPercent);
  }

  //////////
  // View //
  //////////

  function getBasisContingencyParams() external view returns (IPMRMLib_2.BasisContingencyParameters memory) {
    return basisContParams;
  }

  function getOtherContingencyParams() external view returns (IPMRMLib_2.OtherContingencyParameters memory) {
    return otherContParams;
  }

  function getMarginParams() external view returns (IPMRMLib_2.MarginParameters memory) {
    return marginParams;
  }

  function getVolShockParams() external view returns (IPMRMLib_2.VolShockParameters memory) {
    return volShockParams;
  }

  function getSkewShockParams() external view returns (IPMRMLib_2.SkewShockParameters memory) {
    return skewShockParams;
  }

  function getCollateralParameters(address asset) external view returns (IPMRMLib_2.CollateralParameters memory) {
    return collaterals[asset];
  }

  function getBasisContingencyScenarios() external view returns (IPMRM_2.Scenario[] memory scenarios) {
    scenarios = new IPMRM_2.Scenario[](3);
    scenarios[0] = IPMRM_2.Scenario({
      spotShock: basisContParams.scenarioSpotUp,
      volShock: IPMRM_2.VolShockDirection.None,
      dampeningFactor: 1e18
    });
    scenarios[1] = IPMRM_2.Scenario({
      spotShock: basisContParams.scenarioSpotDown,
      volShock: IPMRM_2.VolShockDirection.None,
      dampeningFactor: 1e18
    });
    scenarios[2] =
      IPMRM_2.Scenario({spotShock: DecimalMath.UNIT, volShock: IPMRM_2.VolShockDirection.None, dampeningFactor: 1e18});
  }
}
