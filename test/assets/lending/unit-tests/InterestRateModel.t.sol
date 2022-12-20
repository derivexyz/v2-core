// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../../../src/assets/InterestRateModel.sol";

/**
 * @dev Simple testing for the InterestRateModel
 */
contract UNIT_InterestRateModel is Test {
  using DecimalMath for uint;
  using SafeCast for uint;

  InterestRateModel rateModel;

  function setUp() public {
    uint minRate = 0.06 * 1e18;
    uint rateMultipler = 0.2 * 1e18;
    uint highRateMultipler = 0.4 * 1e18;
    uint optimalUtil = 0.6 * 1e18;

    rateModel = new InterestRateModel(minRate, rateMultipler, highRateMultipler, optimalUtil);
  }

  function testSetNewParams(uint minRate, uint rateMultipler, uint highRate, uint optimalUtil) public {
    rateModel.setInterestRateParams(minRate, rateMultipler, highRate, optimalUtil);
    assertEq(rateModel.minRate(), minRate);
    assertEq(rateModel.rateMultipler(), rateMultipler);
    assertEq(rateModel.highRateMultipler(), highRate);
    assertEq(rateModel.optimalUtil(), optimalUtil);
  }

  function testFuzzUtilizationRate(uint cash, uint borrows) public {
    vm.assume(cash <= 10000000000000000000000000000 ether);
    vm.assume(cash >= borrows);

    uint util = rateModel.getUtilRate(cash, borrows);

    if (borrows == 0) {
      assertEq(util, 0);
    } else {
      assertEq(util, borrows.divideDecimal(cash));
    }
  }

  function testFuzzBorrowRate(uint cash, uint borrows) public {
    vm.assume(cash <= 10000000000000000000000000000 ether);
    vm.assume(cash >= borrows);

    uint util = rateModel.getUtilRate(cash, borrows);
    uint opUtil = rateModel.optimalUtil();
    uint minRate = rateModel.minRate();
    uint lowSlope = rateModel.rateMultipler();
    uint borrowRate = rateModel.getBorrowRate(cash, borrows);

    if (util <= opUtil) {
      uint lowRate = util.multiplyDecimal(lowSlope) + minRate;
      assertEq(borrowRate, lowRate);
    } else {
      uint lowRate = opUtil.multiplyDecimal(lowSlope) + minRate;
      uint excessUtil = util - opUtil;
      uint highSlope = rateModel.highRateMultipler();
      uint highRate = excessUtil.multiplyDecimal(highSlope) + lowRate;
      assertEq(borrowRate, highRate);
    }
  }

  function testFuzzBorrowRate(uint time, uint cash, uint borrows) public {
    vm.assume(cash <= 100000 ether);
    vm.assume(cash >= borrows);
    vm.assume(time >= block.timestamp && time <= block.timestamp + rateModel.SECONDS_PER_YEAR() * 100);

    uint borrowRate = rateModel.getBorrowRate(cash, borrows);
    uint interestFactor = rateModel.getBorrowInterestFactor(time, borrowRate);
    uint calculatedRate =
      FixedPointMathLib.exp((time * borrowRate / rateModel.SECONDS_PER_YEAR()).toInt256()) - DecimalMath.UNIT;

    assertEq(interestFactor, calculatedRate);
  }
}
