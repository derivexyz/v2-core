// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../src/libraries/IntLib.sol";

/**
 * @dev for current `forge coverage` to wrok, i needs to call an external contract then invoke internal library
 */
contract IntLibTester {
  function abs(int a) external pure returns (uint) {
    // it has to store result and return to work!
    uint res = IntLib.abs(a);
    return res;
  }

  function absMin(int a, int b) external pure returns (uint absMinAmount) {
    uint res = IntLib.absMin(a, b);
    return res;
  }

  function min(int a, int b) external pure returns (int res) {
    int res = IntLib.min(a, b);
    return res;
  }

  function max(int a, int b) external pure returns (int res) {
    int res = IntLib.max(a, b);
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

  function testAbsMin() public {
    assertEq(tester.absMin(0, -100), 0);

    assertEq(tester.absMin(-200, -100), 100);

    assertEq(tester.absMin(200, 100), 100);
  }

  function testMin() public {
    assertEq(tester.min(0, -100), -100);
    assertEq(tester.min(-200, -100), -200);
    assertEq(tester.min(200, 100), 100);
  }

  function testMax() public {
    assertEq(tester.max(0, -100), 0);
    assertEq(tester.max(-200, -100), -100);
    assertEq(tester.max(200, 100), 200);
  }
}
