// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/interfaces/AccountStructs.sol";
import "forge-std/console2.sol";

/**
 * @title ArrayLib
 * @author Lyra
 * @notice util functions for array operations
 */

library ArrayLib {
  /**
   * @dev Add unique element to existing "array" if and increase max index
   *      array memory will be updated in place
   * @param array array of number
   * @param newElement number to check
   * @param maxIndex previously recorded max index with non-zero value
   * @return newMaxIndex new max index
   * @return index index of the added element
   */
  function addUniqueToArray(uint[] memory array, uint newElement, uint maxIndex)
    internal
    pure
    returns (uint newMaxIndex, uint index)
  {
    int foundIndex = findInArray(array, newElement, maxIndex);
    if (foundIndex == -1) {
      array[newMaxIndex++] = newElement;
      return (newMaxIndex, newMaxIndex);
    }
    return (maxIndex, uint(foundIndex));
  }

  /**
   * @dev Add unique element to existing "array" if and increase max index
   *      array memory will be updated in place
   * @param array array of address
   * @param newElement address to check
   * @param maxIndex previously recorded max index with non-zero value
   * @return newMaxIndex new max index
   */
  function addUniqueToArray(address[] memory array, address newElement, uint maxIndex)
    internal
    pure
    returns (uint newMaxIndex)
  {
    if (findInArray(array, newElement, maxIndex) == -1) {
      array[maxIndex++] = newElement;
    }
    return maxIndex;
  }

  /**
   * @dev return if a number exists in an array of numbers
   * @param array array of number
   * @param toFind  numbers to find
   * @return index index of the found element. -1 if not found
   */
  function findInArray(uint[] memory array, uint toFind, uint arrayLen) internal pure returns (int index) {
    for (uint i; i < arrayLen; ++i) {
      if (array[i] == 0) {
        return -1;
      }
      if (array[i] == toFind) {
        return int(i);
      }
    }
    return -1;
  }

  /**
   * @dev return if an address exists in an array of address
   * @param array array of address
   * @param toFind  address to find
   * @return index index of the found element. -1 if not found
   */
  function findInArray(address[] memory array, address toFind, uint arrayLen) internal pure returns (int index) {
    for (uint i; i < arrayLen; ++i) {
      if (array[i] == address(0)) {
        return -1;
      }
      if (array[i] == toFind) {
        return int(i);
      }
    }
    return -1;
  }
}
