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
  
  function addUniqueToArray(uint[] storage array, uint newElement, uint arrayLen)
    internal
    returns (uint newArrayLen, uint index)
  {
    int foundIndex = findInArray(array, newElement, arrayLen);
    if (foundIndex == -1) {
      array.push(newElement); // use push here instead of direct assignment
      unchecked {
        return (arrayLen + 1, arrayLen);
      }
    }
    return (arrayLen, uint(foundIndex));
  }


  
  function findInArray(uint[] storage array, uint toFind, uint arrayLen) internal view returns (int index) {
    unchecked {
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
  }
}
