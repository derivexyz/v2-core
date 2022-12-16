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

}

