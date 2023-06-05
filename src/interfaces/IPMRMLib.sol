// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

contract IPMRMLib {
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
    /// @dev Factor for multiplying number of naked shorts (per strike) in the portfolio, multipled by spot.
    uint optionPercent;
  }

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
