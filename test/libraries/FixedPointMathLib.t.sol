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

  function exp(int x) external pure returns (uint r) {
    uint result = FixedPointMathLib.exp(x);
    return result;
  }

  function sqrt(uint x) external pure returns (uint r) {
    uint result = FixedPointMathLib.sqrt(x);
    return result;
  }

  function stdNormal(int x) external pure returns (uint r) {
    uint result = FixedPointMathLib.stdNormal(x);
    return result;
  }

  function stdNormalCDF(int x) external pure returns (uint r) {
    uint result = FixedPointMathLib.stdNormalCDF(x);
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

  function testExpPercise() public {
    // exp(10) = 22026.4657948
    assertEq(tester.expPrecise(10e27), 22026_465794806_716516861_000000000);

    // exp(136) will overflow
    vm.expectRevert(FixedPointMathLib.ExpOverflow.selector);
    tester.expPrecise(136e27);

    // exp(0) = 1
    assertEq(tester.expPrecise(0), 999999999999999999_000000000);

    // exp(-1) = 0.36787944117
    assertEq(tester.expPrecise(-1e27), 367879441_171442321_000000000);
  }

  function testSqrt() public {
    assertEq(tester.sqrt(uint(1e10 * 1e10 * 1e18)), 1e10 * 1e18);

    // sqrt(0.5) = 0.70710678118
    assertEq(tester.sqrt(0.5e18), 707106781_186547524);

    // sqrt(1) = 0.70710678118
    assertEq(tester.sqrt(1e18), 1e18);

    // exp(0) = 1
    assertEq(tester.sqrt(0), 0);
  }

  function testStdNormalCDF() public {
    // stdNormalCDF(1) = 0.84134
    assertEq(tester.stdNormalCDF(1e18), 841344746_068542957);
    assertEq(tester.stdNormalCDF(-1e18), 158655253_931457043); // 1 - stdNormCDF(1)

    // stdNormalCDF(2) = 0.84134
    assertEq(tester.stdNormalCDF(2e18), 977249868_051820775);
    assertEq(tester.stdNormalCDF(-2e18), 22750131_948179225); // 1 - stdNormCDF(2)

    // stdNormalCDF(10) is close to 1
    assertEq(tester.stdNormalCDF(10e18), 1e18);
    assertEq(tester.stdNormalCDF(-10e18), 0);

    // stdNormalCDF(38) is close to 1
    assertEq(tester.stdNormalCDF(38e18), 1e18);
    assertEq(tester.stdNormalCDF(-38e18), 0);

    // stdNormalCDF(0) = 0.5
    assertEq(tester.stdNormalCDF(0), 0.5e18 - 1); // -1 for percision loss
  }

  // https://keisan.casio.com/exec/system/1180573188
  function testStdNormal() public {
    // stdNormal (1) = 0.24197
    assertEq(tester.stdNormal(1e18), 241970724_519143349);
    assertEq(tester.stdNormal(-1e18), 241970724_519143349);

    // stdNormal (2) = 0.05399096651318805195056
    assertEq(tester.stdNormal(2e18), 53990966_513188051);

    // stdNormal (0.5) = 0.3520653267642994777747
    assertEq(tester.stdNormal(0.5e18), 352065326_764299477);
  }
}
