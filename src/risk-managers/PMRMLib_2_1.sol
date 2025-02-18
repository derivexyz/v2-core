// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "../assets/WrappedERC20Asset.sol";
import "lyra-utils/decimals/DecimalMath.sol";
import "lyra-utils/decimals/SignedDecimalMath.sol";
import "lyra-utils/math/Black76.sol";
import {IPMRMLib_2_1} from "../interfaces/IPMRMLib_2_1.sol";
import {IPMRM_2_1} from "../interfaces/IPMRM_2_1.sol";
import {ISpotFeed} from "../interfaces/ISpotFeed.sol";
import {Math} from "openzeppelin/utils/math/Math.sol";

import {Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";
import {SafeCast} from "openzeppelin/utils/math/SafeCast.sol";
import {SignedMath} from "openzeppelin/utils/math/SignedMath.sol";

/**
 * @title PMRMLib
 * @notice Functions for helping compute PMRM value and risk (maintenance/initial margin and MTM)
 * TODO: for secToExpiry == 0, handle it as a special case?
 */
contract PMRMLib_2_1 is IPMRMLib_2_1, Ownable2Step {
  using SignedDecimalMath for int;
  using DecimalMath for uint;
  using SafeCast for uint;
  using SafeCast for int;

  BasisContingencyParameters internal basisContParams;
  OtherContingencyParameters internal otherContParams;
  MarginParameters internal marginParams;
  VolShockParameters internal volShockParams;

  struct StaticDiscountParams {
    uint rfrFactor1Pos;
    uint rfrFactor2Pos;
    uint rfrFactor1Neg;
    uint rfrFactor2Neg;
    uint staticDiscount;
  }

  // TODO: param setters/cleanup
  StaticDiscountParams staticDiscountParams = StaticDiscountParams({
    rfrFactor1Pos: 0.1e18,
    rfrFactor2Pos: 0.1e18,
    rfrFactor1Neg: 0.1e18,
    rfrFactor2Neg: 0.1e18,
    staticDiscount: 0.9e18
  });

  struct SkewShockParams {
    uint linearBaseCap;
    uint absBaseCap;
    uint linearCBase;
    uint absCBase;
    int minKStar;
    int widthScale;
    int volParamStatic;
    int volParamScale;
  }

  // TODO: param setters/cleanup
  SkewShockParams skewShockParams = SkewShockParams({
    linearBaseCap: 0.15e18,
    absBaseCap: 0.2e18,
    linearCBase: 0.1e18,
    absCBase: 0.1e18,
    minKStar: 0.01e18,
    widthScale: 4e18,
    volParamStatic: 1.0e18,
    volParamScale: -0.2e18
  });

  struct CollateralParameters {
    bool enabled;
    bool isRiskCancelling;
    // must be <= 1
    uint marginHaircut;
    // added ON TOP OF marginHaircut
    uint initialMarginHaircut;
    uint confidenceFactor;
  }

  // TODO: param setters/cleanup
  mapping(address => CollateralParameters) public collaterals;

  constructor() Ownable2Step() {}

  ///////////
  // Admin //
  ///////////

  function setBasisContingencyParams(IPMRMLib_2_1.BasisContingencyParameters memory _basisContParams) external onlyOwner {
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
  function setOtherContingencyParams(IPMRMLib_2_1.OtherContingencyParameters memory _otherContParams) external onlyOwner {
    if (
      _otherContParams.pegLossThreshold > 1e18 || _otherContParams.pegLossFactor > 20e18
        || _otherContParams.confThreshold > 1e18 || _otherContParams.confMargin > 1.5e18
      // TODO: bounds
//        || _otherContParams.perpPercent > 1e18 || _otherContParams.optionPercent > 1e18
    ) {
      revert PMRML_InvalidOtherContingencyParameters();
    }
    otherContParams = _otherContParams;
  }

  function setMarginParams(IPMRMLib_2_1.MarginParameters memory _marginParams) external onlyOwner {
    if (
      _marginParams.longRateMultScale > 5e18 || _marginParams.longRateAddScale > 5e18
      // TODO: mmFactor bounds
        || _marginParams.imFactor < 1e18 || _marginParams.imFactor > 4e18
    ) {
      revert PMRML_InvalidMarginParameters();
    }
    marginParams = _marginParams;
  }

  function setVolShockParams(IPMRMLib_2_1.VolShockParameters memory _volShockParams) external onlyOwner {
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

  function setCollateralParameters(
    address asset,
    CollateralParameters memory params
  ) external onlyOwner {
    // TODO: validate params
    // TODO: check if asset exists in pmrm
    collaterals[asset] = params;
  }

  //////////////////////
  // MTM calculations //
  //////////////////////

  /**
   * @return margin The margin result, either IM or MM depending on "isInitial"
   * @return markToMarket The mark-to-market value of the portfolio
   * @return worstScenario The index of the worst scenario, if == scenarios.length, it is the basis contingency
   */
  function getMarginAndMarkToMarket(IPMRM_2_1.Portfolio memory portfolio, bool isInitial, IPMRM_2_1.Scenario[] memory scenarios)
    external
    view
    returns (int margin, int markToMarket, uint worstScenario)
  {
    if (scenarios.length == 0) revert PMRML_InvalidGetMarginState();

    int minSPAN = portfolio.basisContingency;
    worstScenario = scenarios.length;

    for (uint i = 0; i < scenarios.length; ++i) {
      IPMRM_2_1.Scenario memory scenario = scenarios[i];

      // SPAN value with discounting applied, and only the *difference from MtM*
      // TODO: rename MTM -> maxLoss
      int scenarioMTM = getScenarioMtM(portfolio, scenario);
      if (scenarioMTM < minSPAN) {
        minSPAN = scenarioMTM;
        worstScenario = i;
      }
    }

    uint mFactor = isInitial ? marginParams.imFactor : marginParams.mmFactor;

    // peg loss factor
    if (isInitial && portfolio.stablePrice < otherContParams.pegLossThreshold) {
      uint pegLoss = portfolio.stablePrice - portfolio.stablePrice;
      mFactor += pegLoss.multiplyDecimal(otherContParams.pegLossFactor);
    }

    minSPAN = minSPAN.multiplyDecimal(mFactor.toInt256());

    if (isInitial) {
      minSPAN -= portfolio.IMDiscount.toInt256();
    }
    minSPAN -= portfolio.MMDiscount.toInt256();

    return (minSPAN + portfolio.totalMtM + portfolio.cash, portfolio.totalMtM + portfolio.cash, worstScenario);
  }

  // @dev Calculates the DIFFERENCE to the atm MTM
  function getScenarioMtM(IPMRM_2_1.Portfolio memory portfolio, IPMRM_2_1.Scenario memory scenario)
    public
    view
    returns (int scenarioMtM)
  {
    //////////
    // Perp
    scenarioMtM += _getShockedPerpValue(portfolio.perpPosition, portfolio.perpPrice, scenario.spotShock);

    ////////////
    // Option
    for (uint j = 0; j < portfolio.expiries.length; ++j) {
      IPMRM_2_1.ExpiryHoldings memory expiry = portfolio.expiries[j];

      int shockedExpiryMTM;
      // Check cached values
      if (scenario.volShock == IPMRM_2_1.VolShockDirection.None && scenario.spotShock == DecimalMath.UNIT) {
        // we've already calculated this previously, so just use that
        shockedExpiryMTM = expiry.mtm;
      } else if (
        scenario.volShock == IPMRM_2_1.VolShockDirection.None && scenario.spotShock == basisContParams.scenarioSpotUp
      ) {
        // NOTE: this value may not be cached depending on how _addPrecomputes was called; so be careful.
        shockedExpiryMTM = expiry.basisScenarioUpMtM;
      } else if (
        scenario.volShock == IPMRM_2_1.VolShockDirection.None && scenario.spotShock == basisContParams.scenarioSpotDown
      ) {
        // NOTE: this value may not be cached depending on how _addPrecomputes was called; so be careful.
        shockedExpiryMTM = expiry.basisScenarioDownMtM;
      } else if (scenario.volShock == IPMRM_2_1.VolShockDirection.Linear || scenario.volShock == IPMRM_2_1.VolShockDirection.Abs) {
        shockedExpiryMTM = _getExpirySkewedShockedMTM(expiry, scenario.volShock);
      } else {
        // Vol shock is either Up, Down, None
        shockedExpiryMTM = _getExpiryShockedMTM(expiry, scenario.spotShock, scenario.volShock);
      }

      // TODO: double check discount application here
      scenarioMtM += shockedExpiryMTM.multiplyDecimal(expiry.staticDiscount.toInt256());
    }

    ////////////////
    // Collateral
    for (uint j = 0; j < portfolio.collaterals.length; ++j) {
      IPMRM_2_1.CollateralHoldings memory collateral = portfolio.collaterals[j];
      if (!collaterals[address(collateral.asset)].isRiskCancelling) {
        scenarioMtM += collateral.value.toInt256();
        continue;
      }

      scenarioMtM += collateral.value.multiplyDecimal(scenario.spotShock).toInt256();
    }

    // we subtract expiry MtM as we only care about the difference from the current mtm at this stage
    return (scenarioMtM - portfolio.totalMtM).multiplyDecimal(scenario.dampeningFactor.toInt256());
  }

  // calculate MTM with given shock
  function _getExpiryShockedMTM(
    IPMRM_2_1.ExpiryHoldings memory expiry,
    uint spotShock,
    IPMRM_2_1.VolShockDirection volShockDirection
  ) internal view returns (int mtm) {
    uint volShock = DecimalMath.UNIT;
    uint minVol = 0;
    if (volShockDirection == IPMRM_2_1.VolShockDirection.Up) {
      volShock = expiry.volShockUp;
      minVol = volShockParams.minVolUpShock;
    } else if (volShockDirection == IPMRM_2_1.VolShockDirection.Down) {
      volShock = expiry.volShockDown;
    }

    uint64 secToExpiry = expiry.secToExpiry.toUint64();
    uint128 forwardPrice =
      (expiry.forwardVariablePortion.multiplyDecimal(spotShock) + expiry.forwardFixedPortion).toUint128();

    int totalMTM = 0;
    for (uint i = 0; i < expiry.options.length; i++) {
      IPMRM_2_1.StrikeHolding memory option = expiry.options[i];
      uint vol = Math.max(minVol, option.vol.multiplyDecimal(volShock));
      (uint call, uint put) = Black76.prices(
        Black76.Black76Inputs({
          timeToExpirySec: secToExpiry,
          volatility: vol.toUint128(),
          fwdPrice: forwardPrice,
          strikePrice: option.strike.toUint128(),
          discount: 1e18
        })
      );

      totalMTM += (option.isCall ? call.toInt256() : put.toInt256()).multiplyDecimal(option.amount);
    }

    return totalMTM;
  }

  function _getKStar(uint sqrtTau) internal view returns (int) {
    int volParam = skewShockParams.volParamStatic + int(sqrtTau).multiplyDecimal(skewShockParams.volParamScale);
    int kStar = int(sqrtTau).multiplyDecimal(skewShockParams.widthScale).multiplyDecimal(volParam);
    return SignedMath.max(skewShockParams.minKStar, kStar);
  }

  // calculate MTM with given shock
  function _getExpirySkewedShockedMTM(
    IPMRM_2_1.ExpiryHoldings memory expiry,
    IPMRM_2_1.VolShockDirection volShockDirection
  ) internal view returns (int mtm) {
    // either linear or abs
    bool isLinear = volShockDirection == IPMRM_2_1.VolShockDirection.Linear;

    uint64 secToExpiry = expiry.secToExpiry.toUint64();
    uint128 forwardPrice = (expiry.forwardVariablePortion + expiry.forwardFixedPortion).toUint128();

    uint sqrtTau = FixedPointMathLib.sqrt(Black76.annualise(secToExpiry));

    uint multCap;
    if (isLinear) {
      multCap = skewShockParams.linearCBase.multiplyDecimal(sqrtTau) + skewShockParams.linearBaseCap;
    } else {
      multCap = skewShockParams.absCBase.multiplyDecimal(sqrtTau) + skewShockParams.absBaseCap;
    }

    int kStar = _getKStar(sqrtTau);

    int totalMTM = 0;
    for (uint i = 0; i < expiry.options.length; i++) {
      IPMRM_2_1.StrikeHolding memory option = expiry.options[i];

      Black76.Black76Inputs memory inputs = Black76.Black76Inputs({
        timeToExpirySec: secToExpiry,
        volatility: 0,
        fwdPrice: forwardPrice,
        strikePrice: option.strike.toUint128(),
        discount: 1e18
      });

      int k = FixedPointMathLib.ln(int(forwardPrice * 1e18 / option.strike));
      k = isLinear ? k : int(SignedMath.abs(k));

      int skewMultiplier;
      if (k >= 0) {
        skewMultiplier = 1e18 + SignedMath.min(int(multCap), k * int(multCap) / kStar);
      } else {
        skewMultiplier = 1e18 + SignedMath.max(-int(multCap), k * int(multCap) / kStar);
      }

      inputs.volatility = option.vol.multiplyDecimal(skewMultiplier < 0 ? 0 : skewMultiplier.toUint256()).toUint128();

      (uint call, uint put) = Black76.prices(inputs);

      totalMTM += (option.isCall ? call.toInt256() : put.toInt256()).multiplyDecimal(option.amount);
    }

    return totalMTM;
  }

  function _getShockedPerpValue(int position, uint perpPrice, uint spotShock) internal pure returns (int) {
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
  function addPrecomputes(IPMRM_2_1.Portfolio memory portfolio) external view returns (IPMRM_2_1.Portfolio memory) {
    portfolio.totalMtM += portfolio.perpValue;

    uint perpNotional = SignedMath.abs(portfolio.perpPosition).multiplyDecimal(portfolio.spotPrice);

    portfolio.MMDiscount = perpNotional.multiplyDecimal(otherContParams.MMPerpPercent);
    portfolio.IMDiscount = perpNotional.multiplyDecimal(otherContParams.IMPerpPercent);
    portfolio.IMDiscount += _getConfidenceContingency(portfolio.minConfidence, perpNotional);

    for (uint i = 0; i < portfolio.expiries.length; ++i) {
      IPMRM_2_1.ExpiryHoldings memory expiry = portfolio.expiries[i];

      expiry.minConfidence = Math.min(portfolio.minConfidence, expiry.minConfidence);

      // Current MtM and basis contingency MtMs
      expiry.mtm = _getExpiryShockedMTM(expiry, DecimalMath.UNIT, IPMRM_2_1.VolShockDirection.None);
      portfolio.totalMtM += expiry.mtm;

      _addBasisContingency(portfolio, expiry);

      _addVolShocks(expiry);
      _addStaticDiscount(expiry);
      _addOptionContingency(portfolio, expiry, portfolio.spotPrice);
      portfolio.IMDiscount += _getConfidenceContingency(
        expiry.minConfidence, expiry.netOptions, portfolio.spotPrice
      );
    }

    for (uint i=0; i < portfolio.collaterals.length; ++i) {
      IPMRM_2_1.CollateralHoldings memory collateral = portfolio.collaterals[i];
      CollateralParameters memory params = collaterals[address(collateral.asset)];

      portfolio.totalMtM += collateral.value.toInt256();

      portfolio.MMDiscount += collateral.value.multiplyDecimal(params.marginHaircut);
      portfolio.IMDiscount += collateral.value.multiplyDecimal(params.initialMarginHaircut);
      portfolio.IMDiscount += _getConfidenceContingency(collateral.minConfidence, collateral.value);
    }

    return portfolio;
  }

  function _addStaticDiscount(IPMRM_2_1.ExpiryHoldings memory expiry) internal view {
    uint tau = Black76.annualise(expiry.secToExpiry.toUint64());

    if (expiry.mtm > 0) {
      uint shockRfr = expiry.rate.multiplyDecimal(marginParams.longRateMultScale) + marginParams.longRateAddScale;
      expiry.staticDiscount = marginParams.baseStaticDiscount.multiplyDecimal(
        FixedPointMathLib.exp(-(tau.multiplyDecimal(shockRfr).toInt256()))
      );
    } else {
      uint shockRfr = expiry.rate.multiplyDecimal(marginParams.shortRateMultScale) + marginParams.shortRateAddScale;
      expiry.staticDiscount = FixedPointMathLib.exp(-(tau.multiplyDecimal(shockRfr).toInt256()));
    }
  }

  function _addVolShocks(IPMRM_2_1.ExpiryHoldings memory expiry) internal view {
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

  function _addBasisContingency(IPMRM_2_1.Portfolio memory portfolio, IPMRM_2_1.ExpiryHoldings memory expiry) internal view {
    expiry.basisScenarioUpMtM =
      _getExpiryShockedMTM(expiry, basisContParams.scenarioSpotUp, IPMRM_2_1.VolShockDirection.None);
    expiry.basisScenarioDownMtM =
      _getExpiryShockedMTM(expiry, basisContParams.scenarioSpotDown, IPMRM_2_1.VolShockDirection.None);

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

  function _getConfidenceContingency(uint minConfidence, uint notionalAmt) internal view returns (uint) {
    // TODO: should confThreshold be per collateral?
    if (minConfidence < otherContParams.confThreshold) {
      return (DecimalMath.UNIT - minConfidence).multiplyDecimal(otherContParams.confMargin).multiplyDecimal(notionalAmt);
    }
    return 0;
  }

  function _addOptionContingency(
    IPMRM_2_1.Portfolio memory portfolio, IPMRM_2_1.ExpiryHoldings memory expiry, uint spotPrice
  ) internal view returns (uint imContingency, uint mmContingency) {
    uint nakedShorts = 0;
    uint optionsLen = expiry.options.length;
    for (uint i = 0; i < optionsLen; ++i) {
      IPMRM_2_1.StrikeHolding memory option = expiry.options[i];
      if (option.seenInFilter) {
        continue;
      }
      bool found = false;

      for (uint j = i + 1; j < optionsLen; ++j) {
        IPMRM_2_1.StrikeHolding memory option2 = expiry.options[j];

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

    portfolio.MMDiscount += notionalShorts.multiplyDecimal(otherContParams.MMOptionPercent);
    portfolio.IMDiscount += notionalShorts.multiplyDecimal(otherContParams.IMOptionPercent);
  }

  //////////
  // View //
  //////////

  function getBasisContingencyParams() external view returns (IPMRMLib_2_1.BasisContingencyParameters memory) {
    return basisContParams;
  }

  function getVolShockParams() external view returns (IPMRMLib_2_1.VolShockParameters memory) {
    return volShockParams;
  }

  function getStaticDiscountParams() external view returns (IPMRMLib_2_1.MarginParameters memory) {
    return marginParams;
  }

  function getOtherContingencyParams() external view returns (IPMRMLib_2_1.OtherContingencyParameters memory) {
    return otherContParams;
  }

  function getBasisContingencyScenarios() external view returns (IPMRM_2_1.Scenario[] memory scenarios) {
    scenarios = new IPMRM_2_1.Scenario[](3);
    scenarios[0] = IPMRM_2_1.Scenario({spotShock: basisContParams.scenarioSpotUp, volShock: IPMRM_2_1.VolShockDirection.None, dampeningFactor: 1e18});
    scenarios[1] = IPMRM_2_1.Scenario({spotShock: basisContParams.scenarioSpotDown, volShock: IPMRM_2_1.VolShockDirection.None, dampeningFactor: 1e18});
    scenarios[2] = IPMRM_2_1.Scenario({spotShock: DecimalMath.UNIT, volShock: IPMRM_2_1.VolShockDirection.None, dampeningFactor: 1e18});
  }
}
