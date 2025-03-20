// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import {IPMRM_2_1} from "./IPMRM_2_1.sol";

interface IPMRMLib_2_1 {
  struct VolShockParameters {
    /// @dev The max vol shock, that can be scaled down
    uint volRangeUp;
    /// @dev The max
    uint volRangeDown;
    int shortTermPower;
    int longTermPower;
    uint dteFloor;
    uint minVolUpShock;
  }

  struct MarginParameters {
    uint imFactor;
    uint mmFactor;
    uint shortRateMultScale;
    uint longRateMultScale;
    uint shortRateAddScale;
    uint longRateAddScale;
    uint baseStaticDiscount;
  }

  struct BasisContingencyParameters {
    uint scenarioSpotUp;
    uint scenarioSpotDown;
    uint basisContAddFactor;
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
    /// @dev Contingency applied to perps held in the portfolio, multiplied by spot.
    uint MMPerpPercent;
    uint IMPerpPercent;
    /// @dev Factor for multiplying number of naked shorts (per strike) in the portfolio, multiplied by spot.
    uint MMOptionPercent;
    // ADDITIVE ON TOP OF MMOptionPercent
    uint IMOptionPercent;
  }

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
    // must be <= 1
    uint marginHaircut;
    // added ON TOP OF marginHaircut
    uint initialMarginHaircut;
    uint confidenceFactor;
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
  /// @dev emitted when invalid parameters passed into _getMarginAndMarkToMarket
  error PMRM_2_1L_InvalidGetMarginState();
  error PMRM_2_1L_InvalidSkewShockParameters();
  error PMRM_2_1L_InvalidCollateralParameters();
}
