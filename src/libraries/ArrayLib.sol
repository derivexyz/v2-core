pragma solidity ^0.8.13;

import "forge-std/console2.sol";

/**
 * @title ArrayLib
 * @author Lyra
 * @notice util functions to find entity in an array
 */

library ArrayLib {
  /**
   * @dev return if a number exists in an array of numbers
   * @param array array of number
   * @param toFind  numbers to find
   * @return found true if address exists
   */
  function findInArray(uint[] memory array, uint toFind) internal pure returns (bool found) {
    uint arrayLen = array.length;
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
  function findInArray(address[] memory array, address toFind) internal pure returns (bool found) {
    uint arrayLen = array.length;
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