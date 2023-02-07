//SPDX-License-Identifier: ISC

pragma solidity ^0.8.13;

/**
 * @title IntLib
 * @author Lyra
 * @notice util functions for Int
 */

library IntLib {
  /**
   * @notice Returns absolute value.
   * @param amount Positive or negative integer.
   * @return absAmount Absolute value.
   */
  function abs(int amount) internal pure returns (uint absAmount) {
    return amount >= 0 ? uint(amount) : uint(-amount);
  }

  /**
   * @notice Fist takes the absolute value then returns the minimum.
   * @param a First signed integer.
   * @param b Second signed integer.
   * @return absMinAmount Unsigned integer.
   */
  function absMin(int a, int b) internal pure returns (uint absMinAmount) {
    uint absA = abs(a);
    uint absB = abs(b);
    absMinAmount = (absA <= absB) ? absA : absB;
  }

  /**
   * @notice Return the max of 2 integer
   */
  function max(int a, int b) internal pure returns (int) {
    return a > b ? a : b;
  }

  /**
   * @notice Return the in of 2 integer
   */
  function min(int a, int b) internal pure returns (int) {
    return a < b ? a : b;
  }
}
