pragma solidity ^0.8.13;

/**
  * @title Compound's InterestRateModel Interface
  * @author Compound
  */
abstract contract InterestRateModel {
    /// @notice helpful when ensuring valid interestRateModel swap
    bool public constant isInterestRateModel = true;
  
    /**
      * @notice Calculates the current borrow interest rate per block
      * @param cash The total amount of cash the market has
      * @param borrows The total amount of borrows the market has outstanding
      * @param reserves The total amount of reserves the market has
      * @return The borrow rate per block (as a percentage, and scaled by 1e18)
      */
    function getBorrowRate(
      uint cash, uint borrows, uint reserves
    ) virtual external view returns (uint);

    /**
      * @notice Calculates the current supply interest rate per block
      * @param cash The total amount of cash the market has
      * @param borrows The total amount of borrows the market has outstanding
      * @param supply The total amount of supply the market has outstanding
      * @param reserves The total amount of reserves the market has
      * @param reserveFactor The current reserve factor the market has
      * @return The supply rate per block (as a percentage, and scaled by 1e18)
      */
    function getSupplyRate(
      uint cash, uint borrows, uint supply, uint reserves, uint reserveFactor
    ) virtual external view returns (uint);
}