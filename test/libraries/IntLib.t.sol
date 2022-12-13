// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../src/libraries/IntLib.sol";

/**
 * @dev for current `forge coverage` to wrok, i needs to call an external contract then invoke internal library
 */
contract IntLibTester {
  function abs(int a) external view returns (uint) {
    // it has to store result and return to work!
    uint res = IntLib.abs(a);
    return res;
  }
}

contract IntLibTest is Test {
  IntLibTester tester;

  function setUp() public {
    tester = new IntLibTester();
  }

  function testAbsPositive() public {
    int amount = 100;
    assertEq(tester.abs(amount), 100);

    int maxInt = type(int).max;
    assertEq(tester.abs(maxInt), uint(maxInt));
  }

  function testAbsZero() public {
    int amount = 0;
    assertEq(tester.abs(amount), 0);
  }

  function testAbsNegative() public {
    int amount = -100;
    assertEq(tester.abs(amount), 100);

    // the minimum it can handle is min + 1
    int minValue = type(int).min + 1;
    uint expected = type(uint).max / 2;

    assertEq(tester.abs(minValue), expected);
  }

  function testAbsConstraint() public {
    int minInt = type(int).min;
    vm.expectRevert();
    tester.abs(minInt);
  }
}
