// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/utils/math/SafeCast.sol";
import "synthetix/Owned.sol";
import "../libraries/DecimalMath.sol";
import "../libraries/FixedPointMathLib.sol";

/**
 * @title Interest Rate Model
 * @author Lyra
 * @notice Contract that implements the logic for calculating the borrow rate
 */
contract InterestRateModel is Owned {
  using DecimalMath for uint;
  using SafeCast for uint;

  /////////////////////
  // State Variables //
  /////////////////////

  ///@dev The approximate number of seconds per year
  uint public constant SECONDS_PER_YEAR = 365 days;

  ///@dev The base yearly interest rate represented as a mantissa (0-1e18)
  uint public minRate;

  ///@dev The multiplier of utilization rate that gives the slope of the interest rate as a mantissa
  uint public rateMultipler;

  ///@dev The multiplier after hitting the optimal utilization point
  uint public highRateMultipler;

  ///@dev The utilization point at which the highRateMultipler is applied, represented as a mantissa
  uint public optimalUtil;

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
    _setInterestRateParams(_minRate, _rateMultipler, _highRateMultipler, _optimalUtil);
  }

  //////////////////////////////
  //   Owner-only Functions   //
  //////////////////////////////

  /**
   * @notice Allows owner to set the interest rate parameters
   */
  function setInterestRateParams(uint _minRate, uint _rateMultipler, uint _highRateMultipler, uint _optimalUtil)
    external
    onlyOwner
  {
    _setInterestRateParams(_minRate, _rateMultipler, _highRateMultipler, _optimalUtil);
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
    return FixedPointMathLib.exp((elapsedTime * borrowRate / SECONDS_PER_YEAR).toInt256()) - DecimalMath.UNIT;
  }

  /**
   * @notice Calculates the current borrow rate as a linear equation
   * @param supply The supplied amount of stablecoin for the asset
   * @param borrows The amount of borrows in the market
   * @return The borrow rate percentage as a mantissa
   */
  function getBorrowRate(uint supply, uint borrows) external view returns (uint) {
    uint util = getUtilRate(supply, borrows);

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
  function getUtilRate(uint supply, uint borrows) public pure returns (uint) {
    // Utilization rate is 0 when there are no borrows
    if (borrows == 0) {
      return 0;
    }

    return borrows.divideDecimal(supply);
  }

  //////////////
  // Internal //
  //////////////

  function _setInterestRateParams(uint _minRate, uint _rateMultipler, uint _highRateMultipler, uint _optimalUtil)
    internal
    onlyOwner
  {
    if (_minRate > 1e18) revert ParameterMustBeLessThanOne(_minRate);
    if (_rateMultipler > 1e18) revert ParameterMustBeLessThanOne(_rateMultipler);
    if (_highRateMultipler > 1e18) revert ParameterMustBeLessThanOne(_highRateMultipler);
    if (_optimalUtil > 1e18) revert ParameterMustBeLessThanOne(_optimalUtil);
    minRate = _minRate;
    rateMultipler = _rateMultipler;
    highRateMultipler = _highRateMultipler;
    optimalUtil = _optimalUtil;

    emit InterestRateParamsSet(_minRate, _rateMultipler, _highRateMultipler, _optimalUtil);
  }

  ////////////
  // Events //
  ////////////

  ///@dev Emitted when interest rate parameters are set
  event InterestRateParamsSet(uint minRate, uint rateMultipler, uint highRateMultipler, uint optimalUtil);

  ////////////
  // Errors //
  ////////////

  ///@dev Revert when the parameter set is greater than 1e18
  error ParameterMustBeLessThanOne(uint param);
}
