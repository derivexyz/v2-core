// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../src/libraries/DecimalMath.sol";

/**
 * @dev for current `forge coverage` to wrok, i needs to call an external contract then invoke internal library
 */
contract DecimalMathTester {
  function convertDecimals(uint amount, uint8 from, uint8 to) external pure returns (uint) {
    // it has to store result and return to work!
    uint res = DecimalMath.convertDecimals(amount, from, to);
    return res;
  }
}

contract DecimalMathTest is Test {
  using DecimalMath for uint;

  DecimalMathTester tester;

  function setUp() public {
    tester = new DecimalMathTester();
  }

  function testConversionSameDecimals() public {
    uint amount = 1 ether;
    uint result = tester.convertDecimals(amount, 18, 18);
    assertEq(result, amount);
  }

  function testConversionScaleUp() public {
    uint amount = 1 ether;
    uint result = tester.convertDecimals(amount, 18, 20);
    assertEq(result, 100 ether);

    uint result2 = tester.convertDecimals(1e6, 6, 18);
    assertEq(result2, amount);
  }

  function testConversionScaleDown() public {
    uint amount = 1 ether;
    uint result = tester.convertDecimals(amount, 18, 16);
    assertEq(result, 0.01 ether);

    uint result2 = tester.convertDecimals(amount, 18, 6);
    assertEq(result2, 1e6);
  }
}
