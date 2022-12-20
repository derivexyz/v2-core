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

  function testLowUtilBorrowRate() public {
    uint supply = 10000;
    uint borrows = 5000;

    // Borrow rate should be 0.5 * 0.2 + 0.06 = 0.16
    uint lowRate = rateModel.getBorrowRate(supply, borrows);
    assertEq(lowRate, 0.16 * 1e18);
  }

  function testHighUtilBorrowRate() public {
    uint supply = 10000;
    uint borrows = 8000;

    // Borrow rate should be 0.5 * 0.2 + 0.06 = 0.16
    // normal rate = 0.6 * 0.2 + 0.06
    // higher rate = (0.8-0.6) * 0.4 + normal rate (0.18)
    //             = 0.26
    uint highRate = rateModel.getBorrowRate(supply, borrows);
    assertEq(highRate, 0.26 * 1e18);
  }

  function testNoBorrows() public {
    uint supply = 10000;
    uint borrows = 0;

    // Borrow rate should be minRate if util is 0
    uint rate = rateModel.getBorrowRate(supply, borrows);
    assertEq(rate, rateModel.minRate());
  }

  function testFuzzUtilizationRate(uint supply, uint borrows) public {
    vm.assume(supply <= 10000000000000000000000000000 ether);
    vm.assume(supply >= borrows);

    uint util = rateModel.getUtilRate(supply, borrows);

    if (borrows == 0) {
      assertEq(util, 0);
    } else {
      assertEq(util, borrows.divideDecimal(supply));
    }
  }

  function testFuzzBorrowRate(uint supply, uint borrows) public {
    vm.assume(supply <= 10000000000000000000000000000 ether);
    vm.assume(supply >= borrows);

    uint util = rateModel.getUtilRate(supply, borrows);
    uint opUtil = rateModel.optimalUtil();
    uint minRate = rateModel.minRate();
    uint lowSlope = rateModel.rateMultipler();
    uint borrowRate = rateModel.getBorrowRate(supply, borrows);

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

  function testFuzzBorrowRate(uint time, uint supply, uint borrows) public {
    vm.assume(supply <= 100000 ether);
    vm.assume(supply >= borrows);
    vm.assume(time >= block.timestamp && time <= block.timestamp + rateModel.SECONDS_PER_YEAR() * 100);

    uint borrowRate = rateModel.getBorrowRate(supply, borrows);
    uint interestFactor = rateModel.getBorrowInterestFactor(time, borrowRate);
    uint calculatedRate =
      FixedPointMathLib.exp((time * borrowRate / rateModel.SECONDS_PER_YEAR()).toInt256()) - DecimalMath.UNIT;

    assertEq(interestFactor, calculatedRate);
  }
}
