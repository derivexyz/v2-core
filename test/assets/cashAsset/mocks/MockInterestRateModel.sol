// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/utils/math/SafeCast.sol";
import "synthetix/DecimalMath.sol";

/**
 * @title Interest Rate Model
 * @author Lyra
 * @notice Contract that implements the logic for calculating the borrow rate
 */

contract MockInterestRateModel {
  using SafeCast for uint;
  using DecimalMath for uint;

  /////////////////////
  // State Variables //
  /////////////////////

  ///@dev MOCKED static value
  uint public borrowInterestFactor;

  ///@dev MOCKED static value
  uint public borrowRate;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  /**
   * @notice Construct an interest rate model
   * @param _borrowInterestFactor The mocked borrow interest factor
   * @param _borrowRate The mocled borrow rate The rate of increase in interest rate wrt utilization
   */
  constructor(uint _borrowInterestFactor, uint _borrowRate) {
    borrowInterestFactor = _borrowInterestFactor;
    borrowRate = _borrowRate;
  }

  ////////////////////////
  //   Interest Rates   //
  ////////////////////////

  /**
   * @notice MOCKED Function to calculate the interest using a compounded interest rate formula
   *         P_0 * e ^(rt) = Principal with accrued interest
   *
   * @param elapsedTime Seconds since last interest accrual
   * @param borrowRate The current borrow rate for the asset
   * @return Compounded interest rate: e^(rt) - 1
   */
  function getBorrowInterestFactor(uint elapsedTime, uint borrowRate) external view returns (uint) {
    return borrowInterestFactor;
  }

  /**
   * @notice MOCKED Calculates the current borrow rate as a linear equation
   * @param supply The supplied amount of stablecoin for the asset
   * @param borrows The amount of borrows in the market
   * @return The borrow rate percentage as a mantissa
   */
  function getBorrowRate(uint supply, uint borrows) external view returns (uint) {
    return borrowRate;
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

  function test() public {}
}
