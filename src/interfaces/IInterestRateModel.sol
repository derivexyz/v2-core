// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title Inspired by Compound's InterestRateModel Interface
 * @author Lyra
 */
interface IInterestRateModel {

  /**
   * @notice Calculates the current supply interest rate based on total cash and total borrows
   * @param cash The total amount of cash the market has
   * @param borrows The total amount of borrows the market has outstanding
   * @return The supply rate per block (as a percentage, and scaled by 1e18)
   */
  function getSupplyRate(uint cash, uint borrows) external view returns (uint);

  /**
   * @notice Calculates the current borrow interest rate based on total cash and total borrows
   * @param cash The total amount of cash the market has
   * @param borrows The total amount of borrows the market has outstanding
   * @return The borrow rate per block (as a percentage, and scaled by 1e18)
   */
  function getBorrowRate(uint cash, uint borrows) external view returns (uint);
}
