// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../src/libraries/FixedPointMathLib.sol";

/**
 * @dev for current `forge coverage` to wrok, i needs to call an external contract then invoke internal library
 */
contract FixedPointMathTester {
  function lnPrecise(int x) external pure returns (int r) {
    int result = FixedPointMathLib.lnPrecise(x);
    return result;
  }

  function expPrecise(int x) external pure returns (uint r) {
    uint result = FixedPointMathLib.expPrecise(x);
    return result;
  }

  function ln(int x) external pure returns (int r) {
    int result = FixedPointMathLib.ln(x);
    return result;
  }

  function ilog2(uint x) external pure returns (uint r) {
    uint result = FixedPointMathLib.ilog2(x);
    return result;
  }

  function exp(int x) external pure returns (uint r) {
    uint result = FixedPointMathLib.exp(x);
    return result;
  }
}

contract FixedPointMathLibTest is Test {
  FixedPointMathTester tester;

  function setUp() public {
    tester = new FixedPointMathTester();
  }

  function testLn() public {
    // ln(1000) = 6.90775527898
    assertEq(tester.ln(1000e18), 6_907755278_982137052);

    // ln(0.5) = -0.69314718056
    assertEq(tester.ln(0.5e18), -693147180_559945310);

    // ln(1) = 0
    assertEq(tester.ln(1e18), 0);

    // revert with 0
    vm.expectRevert(FixedPointMathLib.Overflow.selector);
    tester.ln(0);

    // revert with negative input
    vm.expectRevert(FixedPointMathLib.LnNegativeUndefined.selector);
    tester.ln(-1);
  }

  function testLnPercise() public {
    // ln(1000) = 6.90775527898, result is 27 decimals
    assertEq(tester.lnPrecise(1000 * 1e27), 6_907755278_982137052_000000000);
    // ln(1) = 0
    assertEq(tester.lnPrecise(1e27), 0);
  }

  function testExp() public {
    // exp(10) = 22026.4657948
    assertEq(tester.exp(10e18), 22026_465794806_716516861);

    // exp(0.5) = 1.6487212707
    assertEq(tester.exp(0.5e18), 1_648721270_700128146);

    // exp(1) = 2.71828182846
    assertEq(tester.exp(1e18), 2_718281828_459045235);

    // exp(135) = 4.2633899e+58
    assertEq(tester.exp(135e18), 42633899483147210448604700672351880453901444390330694182932524274901948249590);

    // exp(136) will overflow
    vm.expectRevert(FixedPointMathLib.ExpOverflow.selector);
    tester.exp(136e18);

    // exp(0) = 1
    assertEq(tester.exp(0), 1e18 - 1); // edge case, returning 0.9999 ...

    // exp(-1) = 0.36787944117
    assertEq(tester.exp(-1e18), 367879441_171442321);

    // exp(-35) = 6.3051168e-16
    assertEq(tester.exp(-35e18), 630);

    // exp(-42) = 5.7495223e-19
    assertEq(tester.exp(-43e18), 0);

    // exp(-41) = 1.5628822e-18
    assertEq(tester.exp(-41e18), 1);
  }
}
