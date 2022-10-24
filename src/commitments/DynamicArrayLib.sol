// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/interfaces/AccountStructs.sol";
import "forge-std/console2.sol";

/**
 * @title ArrayLib
 * @author Lyra
 * @notice util functions for array operations
 */

library DynamicArrayLib {
  function addUniqueToArray(uint96[] storage array, uint96 newElement) internal returns (bool isNew) {
    int foundIndex = findInArray(array, newElement);
    if (foundIndex == -1) {
      array.push(newElement); // use push here instead of direct assignment
      isNew = true;
    }
  }

  function removeFromArray(uint96[] storage array, uint96 element) internal {
    int foundIndex = findInArray(array, element);
    if (foundIndex == -1) return;

    array[uint(foundIndex)] = array[array.length - 1];
    array.pop();
  }

  function findInArray(uint96[] storage array, uint96 toFind) internal view returns (int index) {
    unchecked {
      for (uint i; i < array.length; i++) {
        if (array[i] == toFind) {
          return int(i);
        }
      }
      return -1;
    }
  }
}
