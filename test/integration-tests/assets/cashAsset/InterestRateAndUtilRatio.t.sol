// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../../shared/IntegrationTestBase.sol";

/**
 * @dev testing interest rate and util ratio change given a chain of events
 */
contract INTEGRATION_UtilizationRateTests is IntegrationTestBase {
  function setUp() public {
    _setupIntegrationTestComplete();
  }

  function testUtilRateChanges() public {}
}
