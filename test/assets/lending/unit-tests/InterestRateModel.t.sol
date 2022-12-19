// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../../shared/mocks/MockERC20.sol";
import "../../../shared/mocks/MockManager.sol";

import "../../../../src/assets/Lending.sol";
import "../../../../src/assets/InterestRateModel.sol";
import "../../../../src/Account.sol";

/**
 * @dev we deploy actual Account contract in these tests to simplify verification process
 */
contract UNIT_InterestRateModel is Test {
  using DecimalMath for uint;
  using SafeCast for uint;

  Lending lending;
  InterestRateModel rateModel;
  MockERC20 usdc;
  MockManager manager;
  MockManager badManager;
  Account account;

  uint accountId;
  uint depositedAmount;

  function setUp() public {
    uint minRate = 0.06 * 1e18;
    uint rateMultipler = 0.2 * 1e18;
    uint highRateMultipler = 0.4 * 1e18;
    uint optimalUtil = 0.6 * 1e18;
    
    rateModel = new InterestRateModel(minRate, rateMultipler, highRateMultipler, optimalUtil);
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
  // function testFuzzBorrowRate() public {
    vm.assume(cash <= 100000 ether);
    vm.assume(cash >= borrows);
    vm.assume(time >= block.timestamp); 
    // uint time = block.timestamp;
    // uint cash = 3;
    // uint borrows = 0;

   uint borrowRate = rateModel.getBorrowRate(cash, borrows);
   console.log("borrowRate", borrowRate);

  int test = (time * borrowRate / rateModel.SECONDS_PER_YEAR()).toInt256();
  console.log("test", uint(test));
  uint exp = FixedPointMathLib.exp(test);
  console.log("exp", exp);

   uint interestFactor = rateModel.getBorrowInterestFactor(time, cash, borrows);
   console.log("interestFactor", interestFactor);
   uint calculatedRate = FixedPointMathLib.exp((time * borrowRate / rateModel.SECONDS_PER_YEAR()).toInt256()) - DecimalMath.UNIT;
   assertEq(interestFactor, calculatedRate);
  }


}

