// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;



/**
 * @dev default interest rate params for interest rate model
 */
function getDefaultInterestRateModel() pure returns (
    uint minRate, 
    uint rateMultiplier, 
    uint highRateMultiplier, 
    uint optimalUtil
  ) {
    minRate = 0.06 * 1e18;
    rateMultiplier = 0.2 * 1e18;
    highRateMultiplier = 0.4 * 1e18;
    optimalUtil = 0.6 * 1e18;
  }