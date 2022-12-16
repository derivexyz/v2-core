// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title DecimalMath
 * @author Lyra
 * @notice util functions for converting decimals
 */
library DecimalMath {
  /**
   * @dev convert amount based on decimals
   * @param amount amount in fromDecimals
   * @param fromDecimals original decimals
   * @param toDecimals target decimals
   */
  function convertDecimals(uint amount, uint8 fromDecimals, uint8 toDecimals) internal pure returns (uint) {
    if (fromDecimals == toDecimals) return amount;
    // scale down
    if (fromDecimals > toDecimals) return amount / (10 ** (fromDecimals - toDecimals));
    // scale up
    return amount * (10 ** (toDecimals - fromDecimals));
  }

  /**
   * @dev convert amount to 18 decimals
   * @param amount amount in fromDecimals
   * @param fromDecimals original decimals
   * @return amount in 18 decimals
   */
  function to18Decimals(uint amount, uint8 fromDecimals) internal pure returns (uint) {
    if (fromDecimals == 18) return amount;
    // scale down
    if (fromDecimals > 18) return amount / (10 ** (fromDecimals - 18));
    // scale up
    return amount * (10 ** (18 - fromDecimals));
  }

  /**
   * @dev convert amount from 18 decimals to another decimal based
   * @param amount amount in 18 decimals
   * @param toDecimals target decimals
   * @return amount in toDecimals
   */
  function from18Decimals(uint amount, uint8 toDecimals) internal pure returns (uint) {
    if (18 == toDecimals) return amount;
    // scale down
    if (18 > toDecimals) return amount / (10 ** (18 - toDecimals));
    // scale up
    return amount * (10 ** (toDecimals - 18));
  }
}
