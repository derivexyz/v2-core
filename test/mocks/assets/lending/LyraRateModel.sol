pragma solidity ^0.8.13;

import "synthetix/DecimalMath.sol";
import "synthetix/SignedDecimalMath.sol";
import "./InterestRateModel.sol";

/**
  * @title Modeled off of Compound's JumpRateModel Contract
  * @author Lyra
  */
contract LyraRateModel is InterestRateModel {
  using DecimalMath for uint;

  /**
    * @notice The approximate number of blocks per year 
    *         that is assumed by the interest rate model
    */
  uint public constant blocksPerYear = 2102400;

  /**
    * @notice The multiplier of utilization rate that 
    *         gives the slope of the interest rate
    */
  uint public multiplierPerBlock;

  /**
    * @notice The base interest rate which is the y-intercept 
    *         when utilization rate is 0
    */
  uint public baseRatePerBlock;

  /**
    * @notice The multiplierPerBlock after hitting a specified utilization point
    */
  uint public jumpMultiplierPerBlock;

  /**
    * @notice The utilization point at which the jump multiplier is applied
    */
  uint public kink;

  /**
    * @notice Construct an interest rate model
    * @param baseRatePerYear The approximate target base APR, as a mantissa (scaled by BASE)
    * @param multiplierPerYear The rate of increase in interest rate wrt utilization (scaled by BASE)
    * @param jumpMultiplierPerYear The multiplierPerBlock after hitting a specified utilization point
    * @param kink_ The utilization point at which the jump multiplier is applied
    */
  constructor(
    uint baseRatePerYear, 
    uint multiplierPerYear, 
    uint jumpMultiplierPerYear, 
    uint kink_
  ) {
    baseRatePerBlock = baseRatePerYear / blocksPerYear;
    multiplierPerBlock = multiplierPerYear / blocksPerYear;
    jumpMultiplierPerBlock = jumpMultiplierPerYear / blocksPerYear;
    kink = kink_;

    emit NewInterestParams(baseRatePerBlock, multiplierPerBlock, jumpMultiplierPerBlock, kink);
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

  /**
    * @notice Calculates the current borrow rate per block, with the error code expected by the market
    * @param cash The amount of cash in the market
    * @param borrows The amount of borrows in the market
    * @return The borrow rate percentage per block as a mantissa (scaled by BASE)
    */
  function getBorrowRate(uint cash, uint borrows, uint) override public view returns (uint) {
    uint util = utilizationRate(cash, borrows);

    if (util <= kink) {
        return util.multiplyDecimal(multiplierPerBlock) + baseRatePerBlock;
    } else {
        uint normalRate = kink.multiplyDecimal(multiplierPerBlock) + baseRatePerBlock;
        uint excessUtil = util - kink;
        return excessUtil.multiplyDecimal(jumpMultiplierPerBlock) + normalRate;
    }
  }

  /**
    * @notice Calculates the current supply rate per block
    * @param cash The amount of cash in the market
    * @param borrows The amount of borrows in the market
    * @param reserves The amount of reserves in the market
    * @param reserveFactor The current reserve factor for the market
    * @return The supply rate percentage per block as a mantissa (scaled by BASE)
    */
  function getSupplyRate(uint cash, uint borrows, uint supply, uint reserves, uint reserveFactor) override public view returns (uint) {
    uint oneMinusReserveFactor = DecimalMath.UNIT - reserveFactor;
    uint borrowRate = getBorrowRate(cash, borrows, reserves);
    uint ratePostReserve = borrowRate.multiplyDecimal(oneMinusReserveFactor);
    return ratePostReserve.multiplyDecimal(borrows).divideDecimal(supply);
  }

  event NewInterestParams(uint baseRatePerBlock, uint multiplierPerBlock, uint jumpMultiplierPerBlock, uint kink);
}