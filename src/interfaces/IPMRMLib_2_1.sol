// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import {IPMRM_2_1} from "./IPMRM_2_1.sol";

interface IPMRMLib_2_1 {
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
    /// @dev The baseStaticDiscount for computing static discount for positive expiry MtM discounting
    uint baseStaticDiscount;
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
    bool enabled;
    bool isRiskCancelling;
    /// @dev % value of collateral to subtract from MM. Must be <= 1
    uint MMHaircut;
    /// @dev % value of collateral to subtract from IM. Added on top of MMHaircut. Must be <= 1
    uint IMHaircut;
  }

  function getMarginAndMarkToMarket(
    IPMRM_2_1.Portfolio memory portfolio,
    bool isInitial,
    IPMRM_2_1.Scenario[] memory scenarios
  ) external view returns (int margin, int markToMarket, uint worstScenario);

  function getScenarioMtM(IPMRM_2_1.Portfolio memory portfolio, IPMRM_2_1.Scenario memory scenario)
    external
    view
    returns (int scenarioMtM);

  function addPrecomputes(IPMRM_2_1.Portfolio memory portfolio) external view returns (IPMRM_2_1.Portfolio memory);

  function getBasisContingencyScenarios() external view returns (IPMRM_2_1.Scenario[] memory);

  ////////////
  // Errors //
  ////////////

  /// @dev emitted when provided forward contingency parameters are invalid
  error PMRM_2_1L_InvalidBasisContingencyParameters();
  /// @dev emitted when provided other contingency parameters are invalid
  error PMRM_2_1L_InvalidOtherContingencyParameters();
  /// @dev emitted when provided static discount parameters are invalid
  error PMRM_2_1L_InvalidMarginParameters();
  /// @dev emitted when provided vol shock parameters are invalid
  error PMRM_2_1L_InvalidVolShockParameters();
  /// @dev emitted when provided skew shock parameters are invalid
  error PMRM_2_1L_InvalidSkewShockParameters();
  /// @dev emitted when provided collateral parameters are invalid
  error PMRM_2_1L_InvalidCollateralParameters();
  /// @dev emitted when invalid parameters passed into _getMarginAndMarkToMarket
  error PMRM_2_1L_InvalidGetMarginState();
}
