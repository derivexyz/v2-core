// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../src/libraries/DecimalMath.sol";

/**
 * @dev for current `forge coverage` to wrok, i needs to call an external contract then invoke external library
 */
contract DecimalMathTester {
  function unit() external pure returns (uint) {
    uint result = DecimalMath.unit();
    return result;
  }

  /**
   * @return Provides an interface to PRECISE_UNIT.
   */
  function preciseUnit() external pure returns (uint) {
    uint result = DecimalMath.preciseUnit();
    return result;
  }

  function multiplyDecimal(uint x, uint y) external pure returns (uint) {
    uint result = DecimalMath.multiplyDecimal(x, y);
    return result;
  }

  function multiplyDecimalRoundPrecise(uint x, uint y) external pure returns (uint) {
    uint result = DecimalMath.multiplyDecimalRoundPrecise(x, y);
    return result;
  }

  function multiplyDecimalRound(uint x, uint y) external pure returns (uint) {
    uint result = DecimalMath.multiplyDecimalRound(x, y);
    return result;
  }

  function divideDecimal(uint x, uint y) external pure returns (uint) {
    uint result = DecimalMath.divideDecimal(x, y);
    return result;
  }

  function divideDecimalRound(uint x, uint y) external pure returns (uint) {
    uint result = DecimalMath.divideDecimalRound(x, y);
    return result;
  }

  function divideDecimalRoundPrecise(uint x, uint y) external pure returns (uint) {
    uint result = DecimalMath.divideDecimalRoundPrecise(x, y);
    return result;
  }

  function decimalToPreciseDecimal(uint i) external pure returns (uint) {
    uint result = DecimalMath.decimalToPreciseDecimal(i);
    return result;
  }

  function preciseDecimalToDecimal(uint i) external pure returns (uint) {
    uint result = DecimalMath.preciseDecimalToDecimal(i);
    return result;
  }
}

contract DecimalMathTest is Test {
  DecimalMathTester tester;

  function setUp() public {
    tester = new DecimalMathTester();
  }

  function testConstants() public {
    assertEq(tester.unit(), 1e18);
    assertEq(tester.preciseUnit(), 1e27);
  }

  function testConversion() public {
    assertEq(tester.decimalToPreciseDecimal(0.5e18), 0.5e27);
    assertEq(tester.preciseDecimalToDecimal(0.5e27), 0.5e18);

    assertEq(tester.preciseDecimalToDecimal(1e27 + 1), 1e18);
    assertEq(tester.preciseDecimalToDecimal(1e27 + 0.5e9), 1e18 + 1);
  }

  function testMul() public {
    assertEq(tester.multiplyDecimal(10e18, 10e18), 100e18);
  }

  function testMulRoundPrecise() public {
    // values with 27 decimals
    assertEq(tester.multiplyDecimalRoundPrecise(1000e27, 1000e27), 1000_000e27);
  }

  function testMulRound() public {
    assertEq(tester.multiplyDecimalRound(0.5e18, 1), 1);
  }

  function testDiv() public {
    assertEq(tester.divideDecimal(100e18, 10e18), 10e18);
  }

  function testDivRoundPrecise() public {
    assertEq(tester.divideDecimalRoundPrecise(100e27, 10e27), 10e27);
  }

  function testDivRound() public {
    assertEq(tester.divideDecimalRound(0.5e18, 1), 0.5e36);
    assertEq(tester.divideDecimalRound(10e18, 3e18), 3333333333333333333); // 3.33
    assertEq(tester.divideDecimalRound(20e18, 3e18), 6666666666666666667); // 6.66
  }
}
