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

  function to18Decimals(uint amount, uint8 from) external pure returns (uint) {
    uint res = DecimalMath.to18Decimals(amount, from);
    return res;
  }

  function from18Decimals(uint amount, uint8 to) external pure returns (uint) {
    uint res = DecimalMath.from18Decimals(amount, to);
    return res;
  }

  function multiplyDecimal(uint x, uint y) external pure returns (uint) {
    uint res = DecimalMath.multiplyDecimal(x,y);
    return res;
  }

  function divideDecimal(uint x, uint y) external pure returns (uint) {
    uint res = DecimalMath.divideDecimal(x,y);
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

  function testConversion18To18() public {
    uint amount = 1 ether;
    assertEq(tester.to18Decimals(amount, 18), amount);
    assertEq(tester.from18Decimals(amount, 18), amount);
  }

  function testConversionBetweenLowerAnd18() public {
    uint amountIn6 = 1e6;
    uint amountIn18 = 1e18;
    assertEq(tester.to18Decimals(amountIn6, 6), amountIn18);
    assertEq(tester.from18Decimals(amountIn18, 6), amountIn6);
  }

  function testConversionBetween18AndHigher() public {
    uint amountIn27 = 1e27;
    uint amountIn18 = 1e18;
    assertEq(tester.to18Decimals(amountIn27, 27), amountIn18);
    assertEq(tester.from18Decimals(amountIn18, 27), amountIn27);
  }

  function testFuzzMultiplyDecimal(uint x, uint y) public {
    vm.assume(x < 1e42);
    vm.assume(y < 1e42);
    assertEq(tester.multiplyDecimal(x,y), (x*y)/ 1e18);
  }

  function testFuzzDivideDecimal(uint x, uint y) public {
    vm.assume(x < 1e42);
    vm.assume(y < 1e42);
    vm.assume(y != 0);
    assertEq(tester.divideDecimal(x,y), (x*1e18)/ y);
  }

}
