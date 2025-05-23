// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import {IPMRM_2} from "./IPMRM_2.sol";

interface IPMRMLib_2 {
  struct VolShockParameters {
    /// @dev Multiplicative factor for up vol shocks
    uint volRangeUp;
    /// @dev Multiplicative factor for down vol shocks
    uint volRangeDown;
    /// @dev exponential used for scaling the vol shock for shorter dated expiries (<30dte)
    int shortTermPower;
    /// @dev exponential used for scaling the vol shock for longer dated expiries (>30dte)
    int longTermPower;
    /// @dev Minimum DTE used for scaling the vol shock
    uint dteFloor;
    /// @dev Minimum vol shock applied in vol up scenarios (i.e. use max(shocked vol, minVolUpShock))
    uint minVolUpShock;
  }

  struct MarginParameters {
    /// @dev Multiplicative factor used to scale the minSPAN to get IM
    uint imFactor;
    /// @dev Multiplicative factor used to scale the minSPAN to get MM
    uint mmFactor;
    /// @dev Multiplicative factor for static discount calculation, for negative expiry MtM discounting
    uint shortRateMultScale;
    /// @dev Multiplicative factor for static discount calculation, for positive expiry MtM discounting
    uint longRateMultScale;
    /// @dev Additive factor for static discount calculation, for negative expiry MtM discounting
    uint shortRateAddScale;
    /// @dev Additive factor for static discount calculation, for positive expiry MtM discounting
    uint longRateAddScale;
    /// @dev The baseStaticDiscount for computing static discount for negative expiry MtM discounting
    uint shortBaseStaticDiscount;
    /// @dev The baseStaticDiscount for computing static discount for positive expiry MtM discounting
    uint longBaseStaticDiscount;
  }

  struct BasisContingencyParameters {
    /// @dev the spot shock used for the up scenario for basis contingency
    uint scenarioSpotUp;
    /// @dev the spot shock used for the down scenario for basis contingency
    uint scenarioSpotDown;
    /// @dev factor used in conjunction with mult factor to scale the basis contingency
    uint basisContAddFactor;
    /// @dev factor used in conjunction with add factor to scale the basis contingency
    uint basisContMultFactor;
  }

  struct OtherContingencyParameters {
    /// @dev Below this threshold, we consider the stable asset de-pegged, so we add additional contingency
    uint pegLossThreshold;
    /// @dev If below the peg loss threshold, we add this contingency
    uint pegLossFactor;
    /// @dev Below this threshold, IM is affected by confidence contingency
    uint confThreshold;
    /// @dev Percentage of spot used for confidence contingency, scales with the minimum contingency seen.
    uint confMargin;
    /// @dev Contingency applied to perps held in the portfolio, multiplied by spot
    uint MMPerpPercent;
    /// @dev Contingency applied to perps held in the portfolio, multiplied by spot, added on top of MMPerpPercent
    uint IMPerpPercent;
    /// @dev Factor for multiplying number of naked shorts (per strike) in the portfolio, multiplied by spot.
    uint MMOptionPercent;
    /// @dev Factor for multiplying number of naked shorts (per strike) in the portfolio, multiplied by spot,
    /// added on top of MMOptionPercent for IM
    uint IMOptionPercent;
  }

  /// @dev A collection of parameters used within the abs/linear skew shock scenario calculations
  struct SkewShockParameters {
    uint linearBaseCap;
    uint absBaseCap;
    int linearCBase;
    int absCBase;
    int minKStar;
    int widthScale;
    int volParamStatic;
    int volParamScale;
  }

  // Defined once per collateral
  struct CollateralParameters {
    bool isEnabled;
    bool isRiskCancelling;
    /// @dev % value of collateral to subtract from MM. Must be <= 1
    uint MMHaircut;
    /// @dev % value of collateral to subtract from IM. Added on top of MMHaircut. Must be <= 1
    uint IMHaircut;
  }

  function getMarginAndMarkToMarket(
    IPMRM_2.Portfolio memory portfolio,
    bool isInitial,
    IPMRM_2.Scenario[] memory scenarios
  ) external view returns (int margin, int markToMarket, uint worstScenario);

  function getScenarioPnL(IPMRM_2.Portfolio memory portfolio, IPMRM_2.Scenario memory scenario)
    external
    view
    returns (int scenarioMtM);

  function addPrecomputes(IPMRM_2.Portfolio memory portfolio) external view returns (IPMRM_2.Portfolio memory);

  function getBasisContingencyScenarios() external view returns (IPMRM_2.Scenario[] memory);

  function getCollateralParameters(address collateral) external view returns (CollateralParameters memory);

  ////////////
  // Events //
  ////////////
  event BasisContingencyParamsUpdated(IPMRMLib_2.BasisContingencyParameters basisContParams);
  event OtherContingencyParamsUpdated(IPMRMLib_2.OtherContingencyParameters otherContParams);
  event MarginParamsUpdated(IPMRMLib_2.MarginParameters marginParams);
  event VolShockParamsUpdated(IPMRMLib_2.VolShockParameters volShockParams);
  event SkewShockParamsUpdated(IPMRMLib_2.SkewShockParameters skewShockParams);
  event CollateralParametersUpdated(address asset, IPMRMLib_2.CollateralParameters params);

  ////////////
  // Errors //
  ////////////

  /// @dev emitted when provided forward contingency parameters are invalid
  error PMRML2_InvalidBasisContingencyParameters();
  /// @dev emitted when provided other contingency parameters are invalid
  error PMRML2_InvalidOtherContingencyParameters();
  /// @dev emitted when provided static discount parameters are invalid
  error PMRML2_InvalidMarginParameters();
  /// @dev emitted when provided vol shock parameters are invalid
  error PMRML2_InvalidVolShockParameters();
  /// @dev emitted when provided skew shock parameters are invalid
  error PMRML2_InvalidSkewShockParameters();
  /// @dev emitted when provided collateral parameters are invalid
  error PMRML2_InvalidCollateralParameters();
  /// @dev emitted when invalid parameters passed into _getMarginAndMarkToMarket
  error PMRML2_InvalidGetMarginState();
  /// @dev emitted when doing a risk check on a disabled collateral
  error PMRML2_CollateralDisabled();
}
