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
  uint public constant SECONDS_PER_YEAR = 31536000;

  ///@dev The base yearly interest rate which is the y-intercept when utilization rate is 0
  uint public minRate;

  ///@dev The multiplier of utilization rate that gives the slope of the interest rate
  uint public rateMultipler;

  ///@dev The multiplier after hitting the optimal utilization point
  uint public highRateMultipler;

  ///@dev The utilization point at which the highRateMultipler is applied
  uint public optimalUtil;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  /**
   * @notice Construct an interest rate model
   * @param _minRate The approximate target base APR, as a mantissa
   * @param _rateMultipler The rate of increase in interest rate wrt utilization
   * @param _highRateMultipler The multiplier after hitting a specified utilization point
   * @param _optimalUtil The utilization point at which the highRateMultipler is applied
   */
  constructor(uint _minRate, uint _rateMultipler, uint _highRateMultipler, uint _optimalUtil) {
    minRate = _minRate;
    rateMultipler = _rateMultipler;
    highRateMultipler = _highRateMultipler;
    optimalUtil = _optimalUtil;

    emit InterestRateParamsSet(minRate, rateMultipler, highRateMultipler, optimalUtil);
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
   * @param elapsedTime seconds since last interest accrual
   * @param cash The balance of stablecoin for the cash asset
   * @param borrows total outstanding debt
   * @return InterestFactor : e^(rt) - 1
   */
  function getBorrowInterestFactor(uint elapsedTime, uint cash, uint borrows) external view returns (uint) {
    uint r = getBorrowRate(cash, borrows);
    return FixedPointMathLib.exp((elapsedTime * r / SECONDS_PER_YEAR).toInt256()) - DecimalMath.UNIT;
  }

  /**
   * @notice Calculates the current borrow rate as a linear equation
   * @param cash The balance of stablecoin for the cash asset
   * @param borrows The amount of borrows in the market
   * @return The borrow rate percentage per block as a mantissa (scaled by BASE)
   */
  function getBorrowRate(uint cash, uint borrows) public view returns (uint) {
    uint util = getUtilRate(cash, borrows);

    if (util <= optimalUtil) {
      return util.multiplyDecimal(rateMultipler) + minRate;
    } else {
      uint normalRate = optimalUtil.multiplyDecimal(rateMultipler) + minRate;
      uint excessUtil = util - optimalUtil;
      return excessUtil.multiplyDecimal(highRateMultipler) + normalRate;
    }
  }

  /**
   * @notice Calculates the utilization rate of the market: `borrows / cash`
   * @param cash The balance of stablecoin for the cash asset
   * @param borrows The amount of borrows for the cash asset
   * @return The utilization rate as a mantissa between [0, BASE]
   */
  function getUtilRate(uint cash, uint borrows) public pure returns (uint) {
    // Utilization rate is 0 when there are no borrows
    if (borrows == 0) {
      return 0;
    }

    return borrows.divideDecimal(cash);
  }

  ////////////
  // Events //
  ////////////

  ///@dev Emitted when interest rate parameters are set
  event InterestRateParamsSet(uint minRate, uint rateMultipler, uint highRateMultipler, uint optimalUtil);
}
