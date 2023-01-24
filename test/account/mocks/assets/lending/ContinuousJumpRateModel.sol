// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/utils/math/SafeCast.sol";
import "src/libraries/DecimalMath.sol";
import "src/libraries/SignedDecimalMath.sol";
import "src/libraries/FixedPointMathLib.sol";

import "./InterestRateModel.sol";
import "forge-std/console2.sol";

/**
 * @title Modeled off of Compound's JumpRateModel and Aave's compounding model
 * @author Lyra
 */
contract ContinuousJumpRateModel is InterestRateModel {
  using DecimalMath for uint;
  using SafeCast for uint;

  /**
   * @notice The approximate number of seconds per year
   */
  uint public constant SECONDS_PER_YEAR = 31536000;

  /**
   * @notice The multiplier of utilization rate that
   *         gives the slope of the interest rate
   */
  uint public multiplier;

  /**
   * @notice The base yearly interest rate which is the y-intercept
   *         when utilization rate is 0
   */
  uint public baseRatePerYear;

  /**
   * @notice The multiplier after hitting a specified utilization point
   */
  uint public jumpMultiplier;

  /**
   * @notice The utilization point at which the jump multiplier is applied
   */
  uint public kink;

  /**
   * @notice Construct an interest rate model
   * @param baseRatePerYear_ The approximate target base APR, as a mantissa (scaled by BASE)
   * @param multiplier_ The rate of increase in interest rate wrt utilization (scaled by BASE)
   * @param jumpMultiplier_ The multiplierPerBlock after hitting a specified utilization point
   * @param kink_ The utilization point at which the jump multiplier is applied
   */
  constructor(uint baseRatePerYear_, uint multiplier_, uint jumpMultiplier_, uint kink_) {
    baseRatePerYear = baseRatePerYear_;
    multiplier = multiplier_;
    jumpMultiplier = jumpMultiplier_;
    kink = kink_;

    emit NewInterestParams(baseRatePerYear, multiplier, jumpMultiplier, kink);
  }

  /**
   * @notice Function to calculate the interest using a compounded interest rate formula
   *         P_0 * e ^(rt) = Principal with accrued interest
   *
   * @param elapsedTime seconds since last interest accrual
   * @param cash underlying ERC20 balance
   * @param borrows total outstanding debt
   * @return InterestFactor : e^(rt) - 1
   */
  function getBorrowInterestFactor(uint elapsedTime, uint cash, uint borrows) external view override returns (uint) {
    uint r = getBorrowRate(cash, borrows);
    return FixedPointMathLib.exp((elapsedTime * r / SECONDS_PER_YEAR).toInt256()) - DecimalMath.UNIT;
  }

  /**
   * @notice Calculates the current borrow rate per block, with the error code expected by the market
   * @param cash The amount of cash in the market
   * @param borrows The amount of borrows in the market
   * @return The borrow rate percentage per block as a mantissa (scaled by BASE)
   */
  function getBorrowRate(uint cash, uint borrows) public view override returns (uint) {
    uint util = utilizationRate(cash, borrows);

    if (util <= kink) {
      return util.multiplyDecimal(multiplier) + baseRatePerYear;
    } else {
      uint normalRate = kink.multiplyDecimal(multiplier) + baseRatePerYear;
      uint excessUtil = util - kink;
      return excessUtil.multiplyDecimal(jumpMultiplier) + normalRate;
    }
  }

  /**
   * @notice Calculates the current supply rate per block
   * @param cash The amount of cash in the market
   * @param borrows The amount of borrows in the market
   * @param supply The amount of borrows in the market
   * @param feeFactor The current reserve factor for the market
   * @return The supply rate percentage per block as a mantissa (scaled by BASE)
   */
  function getSupplyRate(uint cash, uint borrows, uint supply, uint feeFactor) public view override returns (uint) {
    uint oneMinusReserveFactor = DecimalMath.UNIT - feeFactor;
    uint borrowRate = getBorrowRate(cash, borrows);
    uint ratePostReserve = borrowRate.multiplyDecimal(oneMinusReserveFactor);
    return ratePostReserve.multiplyDecimal(borrows).divideDecimal(supply);
  }

  /**
   * @notice Calculates the utilization rate of the market: `borrows / cash`
   * @param cash The amount of cash in the market
   * @param borrows The amount of borrows in the market
   * @return The utilization rate as a mantissa between [0, BASE]
   */
  function utilizationRate(uint cash, uint borrows) public pure returns (uint) {
    // Utilization rate is 0 when there are no borrows
    if (borrows == 0) {
      return 0;
    }

    return borrows.divideDecimal(cash);
  }

  event NewInterestParams(uint baseRatePerYear, uint multiplier, uint jumpMultiplier, uint kink);

  // add in a function prefixed with test here to prevent coverage from picking it up.
  function test() public {}
}
