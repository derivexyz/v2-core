pragma solidity ^0.8.13;

import "forge-std/console2.sol";

/**
 * @title ArrayLib
 * @author Lyra
 * @notice util functions to find entity in an array
 */

library ArrayLib {

  /**
   * @dev Add unique element to existing "array" if and increase max index
   *      array memory will be updated in memory directly
   * @param array array of number
   * @param newElement number to check
   * @param maxIndex previously recorded max index with non-zero value
   * @return newIndex new max index
   */
  function addUniqueToArray(uint[] memory array, uint newElement, uint maxIndex) internal pure returns (uint newIndex) {
    if (!findInArray(array, newElement, maxIndex)) {
      array[maxIndex + 1] = newElement;
    }
    return maxIndex;
  }

  /**
   * @dev Add unique element to existing "array" if and increase max index
   *      array memory will be updated in memory directly
   * @param array array of address
   * @param newElement address to check
   * @param maxIndex previously recorded max index with non-zero value
   * @return newIndex new max index
   */
  function addUniqueToArray(address[] memory array, address newElement, uint maxIndex) internal pure returns (uint newIndex) {
    if (!findInArray(array, newElement, maxIndex)) {
      array[maxIndex + 1] = newElement;
    }
    return maxIndex;
  }

  /**
   * @dev return if a number exists in an array of numbers
   * @param array array of number
   * @param toFind  numbers to find
   * @return found true if address exists
   */
  function findInArray(uint[] memory array, uint toFind, uint arrayLen) internal pure returns (bool found) {
    for (uint i; i < arrayLen; ++i) {
      if (array[i] == 0) {
        break;
      }
      if (array[i] == toFind) {
        return true;
      }
    }
  }

  /**
   * @dev return if an address exists in an array of address
   * @param array array of address
   * @param toFind  address to find
   * @return found true if address exists
   */
  function findInArray(address[] memory array, address toFind, uint arrayLen) internal pure returns (bool found) {
    for (uint i; i < arrayLen; ++i) {
      if (array[i] == address(0)) {
        break;
      }
      if (array[i] == toFind) {
        return true;
      }
    }
  }
}