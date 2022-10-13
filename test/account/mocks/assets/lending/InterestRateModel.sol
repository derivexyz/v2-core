// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title Inspired by Compound's InterestRateModel Interface
 *        Adding an end to end getBorrowInterestFactor
 * @author Lyra
 */
abstract contract InterestRateModel {
  /// @notice helpful when ensuring valid interestRateModel swap
  bool public constant isInterestRateModel = true;

  /**
   * @notice Returns the multiple by which to
   *         multiply the borrows to get the accrued interest
   */
  function getBorrowInterestFactor(uint elapsedTime, uint cash, uint borrows) external view virtual returns (uint);

  /**
   * @notice Calculates the current borrow interest rate per block
   * @param cash The total amount of cash the market has
   * @param borrows The total amount of borrows the market has outstanding
   * @return The borrow rate per block (as a percentage, and scaled by 1e18)
   */
  function getBorrowRate(uint cash, uint borrows) external view virtual returns (uint);

  /**
   * @notice Calculates the current supply interest rate per block
   * @param cash The total amount of cash the market has
   * @param borrows The total amount of borrows the market has outstanding
   * @param supply The amount of borrows in the market
   * @param feeFactor The current reserve factor the market has
   * @return The supply rate per block (as a percentage, and scaled by 1e18)
   */
  function getSupplyRate(uint cash, uint borrows, uint supply, uint feeFactor) external view virtual returns (uint);
}
