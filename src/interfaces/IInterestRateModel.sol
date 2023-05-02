// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface IInterestRateModel {
  /**
   * @notice Function to calculate the interest on debt balances
   *
   * @param elapsedTime Seconds since last interest accrual
   * @param borrowRate The current borrow rate for the asset
   * @return Interest factor accumlated in the elapsedTime
   */
  function getBorrowInterestFactor(uint elapsedTime, uint borrowRate) external pure returns (uint);

  /**
   * @notice Calculates the current borrow rate as a linear equation
   * @param supply The supplied amount of stablecoin for the asset
   * @param borrows The amount of borrows in the market
   * @return The borrow rate percentage as a mantissa
   */
  function getBorrowRate(uint supply, uint borrows) external view returns (uint);

  /**
   * @notice Calculates the utilization rate of the market: `borrows / supply`
   * @param supply The supplied amount of stablecoin for the asset
   * @param borrows The amount of borrows for the asset
   * @return The utilization rate as a mantissa between
   */
  function getUtilRate(uint supply, uint borrows) external pure returns (uint);

  ////////////
  // Events //
  ////////////

  ///@dev Emitted when interest rate parameters are set
  event InterestRateParamsSet(uint minRate, uint rateMultiplier, uint highRateMultiplier, uint optimalUtil);

  ////////////
  // Errors //
  ////////////

  ///@dev Revert when the parameter set is greater than 1e18
  error IRM_ParameterMustBeLessThanOne(uint param);
  error IRM_NoElapsedTime(uint elapsedTime);
}
