// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title DecimalMath
 * @author Lyra
 * @notice util functions for converting decimals
 */
library DecimalMath {
  // The number representing 1.0
  uint public constant UNIT = 1e18;

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

  /**
   * @dev A unit factor is divided out after the product of x and y is evaluated,
   * so that product must be less than 2**256.
   * @return The result of multiplying x and y, interpreting the operands as fixed-point
   * decimals.
   */
  function multiplyDecimal(uint x, uint y) internal pure returns (uint) {
    /* Divide by UNIT to remove the extra factor introduced by the product. */
    return (x * y) / UNIT;
  }

  /**
   * @dev y is divided after the product of x and the standard precision unit
   * is evaluated, so the product of x and UNIT must be less than 2**256.
   * @return The result of safely dividing x and y. The return value is a high
   * precision decimal.
   */
  function divideDecimal(uint x, uint y) internal pure returns (uint) {
    /* Reintroduce the UNIT factor that will be divided out by y. */
    return (x * UNIT) / y;
  }
}
