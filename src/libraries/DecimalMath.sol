// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title ArrayLib
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
