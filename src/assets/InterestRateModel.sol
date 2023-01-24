// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/utils/math/SafeCast.sol";
import "../libraries/ConvertDecimals.sol";
import "../libraries/FixedPointMathLib.sol";
import "synthetix/DecimalMath.sol";
import "../interfaces/IInterestRateModel.sol";

/**
 * @title Interest Rate Model
 * @author Lyra
 * @notice Contract that implements the logic for calculating the borrow rate
 */

contract InterestRateModel is IInterestRateModel {
  using ConvertDecimals for uint;
  using SafeCast for uint;
  using DecimalMath for uint;

  /////////////////////
  // State Variables //
  /////////////////////

  ///@dev The base yearly interest rate represented as a mantissa (0-1e18)
  uint public immutable minRate;

  ///@dev The multiplier of utilization rate that gives the slope of the interest rate as a mantissa
  uint public immutable rateMultipler;

  ///@dev The multiplier after hitting the optimal utilization point
  uint public immutable highRateMultipler;

  ///@dev The utilization point at which the highRateMultipler is applied, represented as a mantissa
  uint public immutable optimalUtil;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  /**
   * @notice Construct an interest rate model
   * @param _minRate The approximate target base APR
   * @param _rateMultipler The rate of increase in interest rate wrt utilization
   * @param _highRateMultipler The multiplier after hitting a specified utilization point
   * @param _optimalUtil The utilization point at which the highRateMultipler is applied
   */
  constructor(uint _minRate, uint _rateMultipler, uint _highRateMultipler, uint _optimalUtil) {
    if (_minRate > 1e18) revert IRM_ParameterMustBeLessThanOne(_minRate);
    if (_rateMultipler > 1e18) revert IRM_ParameterMustBeLessThanOne(_rateMultipler);
    if (_highRateMultipler > 1e18) revert IRM_ParameterMustBeLessThanOne(_highRateMultipler);
    if (_optimalUtil > 1e18) revert IRM_ParameterMustBeLessThanOne(_optimalUtil);
    minRate = _minRate;
    rateMultipler = _rateMultipler;
    highRateMultipler = _highRateMultipler;
    optimalUtil = _optimalUtil;

    emit InterestRateParamsSet(_minRate, _rateMultipler, _highRateMultipler, _optimalUtil);
  }

  ////////////////////////
  //   Interest Rates   //
  ////////////////////////

  /**
   * @notice Function to calculate the interest using a compounded interest rate formula
   *         P_0 * e ^(rt) = Principal with accrued interest
   *
   * @param elapsedTime Seconds since last interest accrual
   * @param borrowRate The current borrow rate for the asset
   * @return Compounded interest rate: e^(rt) - 1
   */
  function getBorrowInterestFactor(uint elapsedTime, uint borrowRate) external pure returns (uint) {
    if (elapsedTime == 0) revert IRM_NoElapsedTime(elapsedTime);
    return FixedPointMathLib.exp((elapsedTime * borrowRate / 365 days).toInt256()) - ConvertDecimals.UNIT;
  }

  /**
   * @notice Calculates the current borrow rate as a linear equation
   * @param supply The supplied amount of stablecoin for the asset
   * @param borrows The amount of borrows in the market
   * @return The borrow rate percentage as a mantissa
   */
  function getBorrowRate(uint supply, uint borrows) external view returns (uint) {
    uint util = _getUtilRate(supply, borrows);

    if (util <= optimalUtil) {
      return util.multiplyDecimal(rateMultipler) + minRate;
    } else {
      uint normalRate = optimalUtil.multiplyDecimal(rateMultipler) + minRate;
      uint excessUtil = util - optimalUtil;
      return excessUtil.multiplyDecimal(highRateMultipler) + normalRate;
    }
  }

  /**
   * @notice Calculates the utilization rate of the market: `borrows / supply`
   * @param supply The supplied amount of stablecoin for the asset
   * @param borrows The amount of borrows for the asset
   * @return The utilization rate as a mantissa between
   */
  function getUtilRate(uint supply, uint borrows) external pure returns (uint) {
    return _getUtilRate(supply, borrows);
  }

  function _getUtilRate(uint supply, uint borrows) internal pure returns (uint) {
    // Utilization rate is 0 when there are no borrows
    if (borrows == 0) {
      return 0;
    }

    return borrows.divideDecimal(supply);
  }
}
