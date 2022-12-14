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
     * @param arrayLen previously recorded array length with non-zero value
     * @return newArrayLen new length of array
     * @return index index of the added element
     */
    function addUniqueToArray(
        uint256[] memory array,
        uint256 newElement,
        uint256 arrayLen
    )
        internal
        pure
        returns (uint256 newArrayLen, uint256 index)
    {
        int256 foundIndex = findInArray(array, newElement, arrayLen);
        if (foundIndex == -1) {
            array[arrayLen] = newElement;
            unchecked {
                return (arrayLen + 1, arrayLen);
            }
        }
        return (arrayLen, uint256(foundIndex));
    }

    /**
     * @dev Add unique element to existing "array" if and increase max index
     *      array memory will be updated in place
     * @param array array of address
     * @param newElement address to check
     * @param arrayLen previously recorded array length with non-zero value
     * @return newArrayLen new length of array
     */
    function addUniqueToArray(
        address[] memory array,
        address newElement,
        uint256 arrayLen
    )
        internal
        pure
        returns (uint256 newArrayLen)
    {
        if (findInArray(array, newElement, arrayLen) == -1) {
            unchecked {
                array[arrayLen++] = newElement;
            }
        }
        return arrayLen;
    }

    /**
     * @dev return if a number exists in an array of numbers
     * @param array array of number
     * @param toFind  numbers to find
     * @return index index of the found element. -1 if not found
     */
    function findInArray(
        uint256[] memory array,
        uint256 toFind,
        uint256 arrayLen
    )
        internal
        pure
        returns (int256 index)
    {
        unchecked {
            for (uint256 i; i < arrayLen; ++i) {
                if (array[i] == 0) {
                    return -1;
                }
                if (array[i] == toFind) {
                    return int256(i);
                }
            }
            return -1;
        }
    }

    /**
     * @dev return if an address exists in an array of address
     * @param array array of address
     * @param toFind  address to find
     * @return index index of the found element. -1 if not found
     */
    function findInArray(
        address[] memory array,
        address toFind,
        uint256 arrayLen
    )
        internal
        pure
        returns (int256 index)
    {
        unchecked {
            for (uint256 i; i < arrayLen; ++i) {
                if (array[i] == address(0)) {
                    return -1;
                }
                if (array[i] == toFind) {
                    return int256(i);
                }
            }
            return -1;
        }
    }
}
