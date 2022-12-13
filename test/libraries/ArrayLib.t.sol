// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../src/libraries/ArrayLib.sol";

/**
 * @dev for current `forge coverage` to wrok, i needs to call an external contract then invoke internal library
 */
contract ArrayLibTester {
  function addUniqueToArray(uint[] memory array, uint newElement, uint arrayLen)
    external
    pure
    returns (uint[] memory, uint, uint)
  {
    // array is updated in memory, but won't affect the caller's data
    (uint newArrayLen, uint index) = ArrayLib.addUniqueToArray(array, newElement, arrayLen);

    // return array too, just so we can verify in tests
    return (array, newArrayLen, index);
  }

  function addUniqueToArray(address[] memory array, address newElement, uint arrayLen)
    external
    pure
    returns (address[] memory, uint)
  {
    // array is updated in memory, but won't affect the caller's data
    // only return new array length
    uint newArrayLen = ArrayLib.addUniqueToArray(array, newElement, arrayLen);

    // return array too, just so we can verify in tests
    return (array, newArrayLen);
  }
}

contract ArrayLibTest is Test {
  ArrayLibTester tester;

  function setUp() public {
    tester = new ArrayLibTester();
  }

  /* ------------------------- *
   *    uint array functions   *
   * ------------------------- */

  function testAddUniqueUnitToArray() public {
    uint[] memory emptyArr = new uint[](5);

    (uint[] memory arr, uint len, uint index) = tester.addUniqueToArray(emptyArr, 5, 0);
    assertEq(arr[0], 5);
    assertEq(len, 1);
    assertEq(index, 0);

    // add same element to arr again
    (arr, len, index) = tester.addUniqueToArray(arr, 5, len);
    assertEq(arr[0], 5);
    assertEq(len, 1);
    assertEq(index, 0);
  }

  function testAddUniqueUintLengthTooLarge() public {
    uint[] memory emptyArr = new uint[](5);

    // we should pass in 0 here as we no there are no entries in the array
    // if we pass in the wrong length, the entry will be added to the wrong index
    uint wrongLengthToPass = 1;
    (uint[] memory arr, uint len, uint index) = tester.addUniqueToArray(emptyArr, 5, wrongLengthToPass);
    assertEq(arr[0], 0); // index 0 remains empty
    assertEq(arr[1], 5); // 1 got added to index 1
    assertEq(len, 2);
    assertEq(index, 1);

    // first entry is empty, it will append the array directly without checking
    (arr, len, index) = tester.addUniqueToArray(arr, 5, len);
    assertEq(arr[0], 0);
    assertEq(arr[1], 5);
    assertEq(arr[2], 5);
    assertEq(len, 3);
    assertEq(index, 2);
  }

  function testAddUniqueUintLengthTooSmall() public {
    uint[] memory nonEmptyArr = new uint[](5);
    nonEmptyArr[0] = 1;
    nonEmptyArr[1] = 100;

    // we should pass in 2 here.
    // passing in 1 will make the function only check the index 0, and append the result on index 1
    uint wrongLengthToPass = 1;
    (uint[] memory arr, uint len, uint index) = tester.addUniqueToArray(nonEmptyArr, 5, wrongLengthToPass);
    assertEq(arr[0], 1); // index 0 remains empty
    assertEq(arr[1], 5); // 1 got added to index 1
    assertEq(len, 2);
    assertEq(index, 1);
  }

  /* --------------------------- *
   *   address array functions   *
   * -------------------------- */

  function testAddUniqueAddrToArray() public {
    address[] memory emptyArr = new address[](5);

    address element = address(5);

    (address[] memory arr, uint len) = tester.addUniqueToArray(emptyArr, element, 0);
    assertEq(arr[0], element);
    assertEq(len, 1);

    // add same element to arr again
    (arr, len) = tester.addUniqueToArray(arr, element, len);
    assertEq(arr[0], element);
    assertEq(len, 1);
  }

  function testAddUniqueAddrLengthTooLarge() public {
    address[] memory emptyArr = new address[](5);

    address element = address(5);

    // we should pass in 0 here as we no there are no entries in the array
    // if we pass in the wrong length, the entry will be added to the wrong index
    uint wrongLengthToPass = 1;
    (address[] memory arr, uint len) = tester.addUniqueToArray(emptyArr, element, wrongLengthToPass);
    assertEq(arr[0], address(0)); // index 0 remains empty
    assertEq(arr[1], element); // address(5) got added to index 1
    assertEq(len, 2);

    // first entry is empty, so it will append the array directly without checking
    (arr, len) = tester.addUniqueToArray(arr, element, len);
    assertEq(arr[0], address(0));
    assertEq(arr[1], element);
    assertEq(arr[2], element);
    assertEq(len, 3);
  }

  function testAddUniqueAddrLengthTooSmall() public {
    address[] memory nonEmptyArr = new address[](5);
    nonEmptyArr[0] = address(1);
    nonEmptyArr[1] = address(100);

    address element = address(5);

    // we should pass in 2 here.
    // passing in 1 will make the function only check the index 0, and append the result on index 1
    uint wrongLengthToPass = 1;
    (address[] memory arr, uint len) = tester.addUniqueToArray(nonEmptyArr, element, wrongLengthToPass);
    assertEq(arr[0], address(1)); // index 0 remains empty
    assertEq(arr[1], element); // 1 got added to index 1
    assertEq(len, 2);
  }
}
