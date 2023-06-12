// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../../../../src/assets/InterestRateModel.sol";
import "lyra-utils/decimals/DecimalMath.sol";
import "lyra-utils/decimals/ConvertDecimals.sol";

/**
 * @dev Simple testing for the InterestRateModel
 */

contract UNIT_InterestRateModel is Test {
  using ConvertDecimals for uint;
  using SafeCast for uint;
  using DecimalMath for uint;

  InterestRateModel rateModel;

  function setUp() public {
    uint minRate = 0.06 * 1e18;
    uint rateMultiplier = 0.2 * 1e18;
    uint highRateMultiplier = 0.4 * 1e18;
    uint optimalUtil = 0.6 * 1e18;

    rateModel = new InterestRateModel(minRate, rateMultiplier, highRateMultiplier, optimalUtil);
  }
}
