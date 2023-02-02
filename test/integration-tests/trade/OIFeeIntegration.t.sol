// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../shared/setup.sol";

/**
 * @dev testing open interest before and after
 * asset transfers
 * single side adjustments
 */
contract INTEGRATION_OIFeeTest is IntegrationTestBase {
  function setUp() public {
    deployAllV2Contracts();
  }

  function testDeployed() public {
    uint a = 1;
    assertEq(a, 1);
  }
}
