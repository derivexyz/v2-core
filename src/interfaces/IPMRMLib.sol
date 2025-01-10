// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import {IPMRM} from "./IPMRM.sol";

interface IPMRMLib {
  struct VolShockParameters {
    /// @dev The max vol shock, that can be scaled down
    uint volRangeUp;
    /// @dev The max
    uint volRangeDown;
    int shortTermPower;
    int longTermPower;
    uint dteFloor;
  }

  struct MarginParameters {
    uint imFactor;
    uint rateMultScale;
    uint rateAddScale;
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
    /// @dev Contingency applied to base held in the portfolio, multiplied by spot.
    uint basePercent;
    /// @dev Contingency applied to perps held in the portfolio, multiplied by spot.
    uint perpPercent;
    /// @dev Factor for multiplying number of naked shorts (per strike) in the portfolio, multiplied by spot.
    uint optionPercent;
  }

  function getMarginAndMarkToMarket(IPMRM.Portfolio memory portfolio, bool isInitial, IPMRM.Scenario[] memory scenarios)
    external
    view
    returns (int margin, int markToMarket, uint worstScenario);

  function getScenarioMtM(IPMRM.Portfolio memory portfolio, IPMRM.Scenario memory scenario)
    external
    view
    returns (int scenarioMtM);

  function addPrecomputes(IPMRM.Portfolio memory portfolio) external view returns (IPMRM.Portfolio memory);

  function getBasisContingencyScenarios() external view returns (IPMRM.Scenario[] memory);

  ////////////
  // Errors //
  ////////////

  /// @dev emitted when provided forward contingency parameters are invalid
  error PMRML_InvalidBasisContingencyParameters();
  /// @dev emitted when provided other contingency parameters are invalid
  error PMRML_InvalidOtherContingencyParameters();
  /// @dev emitted when provided static discount parameters are invalid
  error PMRML_InvalidMarginParameters();
  /// @dev emitted when provided vol shock parameters are invalid
  error PMRML_InvalidVolShockParameters();
  /// @dev emitted when invalid parameters passed into _getMarginAndMarkToMarket
  error PMRML_InvalidGetMarginState();
}
