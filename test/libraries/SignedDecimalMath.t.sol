// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../src/libraries/SignedDecimalMath.sol";

/**
 * @dev for current `forge coverage` to wrok, i needs to call an external contract then invoke external library
 */
contract SignedDecimalMathTester {
  function unit() external pure returns (int) {
    int result = SignedDecimalMath.unit();
    return result;
  }

  /**
   * @return Provides an interface to PRECISE_UNIT.
   */
  function preciseUnit() external pure returns (int) {
    int result = SignedDecimalMath.preciseUnit();
    return result;
  }

  function multiplyDecimal(int x, int y) external pure returns (int) {
    int result = SignedDecimalMath.multiplyDecimal(x, y);
    return result;
  }

  function multiplyDecimalRoundPrecise(int x, int y) external pure returns (int) {
    int result = SignedDecimalMath.multiplyDecimalRoundPrecise(x, y);
    return result;
  }

  function multiplyDecimalRound(int x, int y) external pure returns (int) {
    int result = SignedDecimalMath.multiplyDecimalRound(x, y);
    return result;
  }

  function divideDecimal(int x, int y) external pure returns (int) {
    int result = SignedDecimalMath.divideDecimal(x, y);
    return result;
  }

  function divideDecimalRound(int x, int y) external pure returns (int) {
    int result = SignedDecimalMath.divideDecimalRound(x, y);
    return result;
  }

  function divideDecimalRoundPrecise(int x, int y) external pure returns (int) {
    int result = SignedDecimalMath.divideDecimalRoundPrecise(x, y);
    return result;
  }

  function decimalToPreciseDecimal(int i) external pure returns (int) {
    int result = SignedDecimalMath.decimalToPreciseDecimal(i);
    return result;
  }

  function preciseDecimalToDecimal(int i) external pure returns (int) {
    int result = SignedDecimalMath.preciseDecimalToDecimal(i);
    return result;
  }
}

contract SignedDecimalMathTest is Test {
  SignedDecimalMathTester tester;

  function setUp() public {
    tester = new SignedDecimalMathTester();
  }

  function testConstants() public {
    assertEq(tester.unit(), 1e18);
    assertEq(tester.preciseUnit(), 1e27);
  }

  function testConversion() public {
    assertEq(tester.decimalToPreciseDecimal(0.5e18), 0.5e27);
    assertEq(tester.preciseDecimalToDecimal(0.5e27), 0.5e18);
  }

  function testMul() public {
    assertEq(tester.multiplyDecimal(10e18, 10e18), 100e18);
    assertEq(tester.multiplyDecimal(-10e18, 10e18), -100e18);
    assertEq(tester.multiplyDecimal(-10e18, -10e18), 100e18);
  }

  function testMulRoundPrecise() public {
    // values with 27 decimals
    assertEq(tester.multiplyDecimalRoundPrecise(1000e27, 1000e27), 1000_000e27);
    assertEq(tester.multiplyDecimalRoundPrecise(-1000e27, 1000e27), -1000_000e27);
  }

  function testMulRound() public {
    assertEq(tester.multiplyDecimalRound(0.5e18, 1), 1);
    assertEq(tester.multiplyDecimalRound(-0.5e18, 1), -1);
  }

  function testDiv() public {
    assertEq(tester.divideDecimal(100e18, 10e18), 10e18);
    assertEq(tester.divideDecimal(-100e18, 10e18), -10e18);
  }

  function testDivRoundPrecise() public {
    assertEq(tester.divideDecimalRoundPrecise(100e27, 10e27), 10e27);
    assertEq(tester.divideDecimalRoundPrecise(-100e27, 10e27), -10e27);
  }

  function testDivRound() public {
    assertEq(tester.divideDecimalRound(0.5e18, 1), 0.5e36);
    assertEq(tester.divideDecimalRound(10e18, 3e18), 3333333333333333333); // 3.33
    assertEq(tester.divideDecimalRound(20e18, 3e18), 6666666666666666667); // 6.66
    assertEq(tester.divideDecimalRound(-10e18, 3e18), -3333333333333333333);
    assertEq(tester.divideDecimalRound(-20e18, 3e18), -6666666666666666667);
  }
}
