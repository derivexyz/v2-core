// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "openzeppelin/utils/math/SafeCast.sol";
import "lyra-utils/decimals/DecimalMath.sol";

import "../../../../src/interfaces/IInterestRateModel.sol";

/**
 * @title Interest Rate Model
 * @author Lyra
 * @notice Contract that implements the logic for calculating the borrow rate
 */

contract MockInterestRateModel is IInterestRateModel {
  using SafeCast for uint;
  using DecimalMath for uint;

  /////////////////////
  // State Variables //
  /////////////////////

  ///@dev MOCKED static value
  uint public borrowRate;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  /**
   * @notice Construct an interest rate model
   * @param _borrowRate The mocled borrow rate The rate of increase in interest rate wrt utilization
   */
  constructor(uint _borrowRate) {
    borrowRate = _borrowRate;
  }

  ////////////////////////
  //   Interest Rates   //
  ////////////////////////

  /**
   * @notice MOCKED Function to calculate the interest using a compounded interest rate formula
   *         P_0 * e ^(rt) = Principal with accrued interest
   *
   * @return Compounded interest rate: e^(rt) - 1
   */
  function getBorrowInterestFactor(uint, /*_elapsedTime*/ uint /*_borrowRate*/ ) external pure override returns (uint) {
    return 0.5 * 1e18; // must be pure function
  }

  /**
   * @notice MOCKED Calculates the current borrow rate as a linear equation
   * @return The borrow rate percentage as a mantissa
   */
  function getBorrowRate(uint, /*supply*/ uint /*borrows*/ ) external view returns (uint) {
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
