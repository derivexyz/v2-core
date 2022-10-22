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
  function addUniqueToArray(uint[] storage array, uint newElement) internal {
    int foundIndex = findInArray(array, newElement);
    if (foundIndex == -1) {
      array.push(newElement); // use push here instead of direct assignment
    }
  }

  function removeFromArray(uint[] storage array, uint element) internal {
    int foundIndex = findInArray(array, element);
    if (foundIndex == -1) return;

    array[uint(foundIndex)] = array[array.length - 1];
    array.pop();
  }

  function findInArray(uint[] storage array, uint toFind) internal view returns (int index) {
    unchecked {
      for (uint i; i < array.length; ++i) {
        if (array[i] == 0) {
          return -1;
        }
        if (array[i] == toFind) {
          return int(i);
        }
      }
      return -1;
    }
  }
}
