// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

contract IPMRMLib {
  struct VolShockParameters {
    uint volRangeUp;
    uint volRangeDown;
    int shortTermPower;
    int longTermPower;
    uint dteFloor;
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
    uint confidenceFactor;
    uint basePercent;
    uint perpPercent;
    /// @dev Factor for multiplying number of naked shorts (per strike) in the portfolio
    uint optionPercent;
  }

  ////////////
  // Errors //
  ////////////

  /// @dev emitted when provided forward contingency parameters are invalid
  error PMRML_InvalidForwardContingencyParameters();
  /// @dev emitted when provided other contingency parameters are invalid
  error PMRML_InvalidOtherContingencyParameters();
  /// @dev emitted when provided static discount parameters are invalid
  error PMRML_InvalidStaticDiscountParameters();
  /// @dev emitted when provided vol shock parameters are invalid
  error PMRML_InvalidVolShockParameters();
}
