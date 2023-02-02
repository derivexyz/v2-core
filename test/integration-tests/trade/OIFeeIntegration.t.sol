// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../shared/IntegrationTestBase.sol";
import "src/interfaces/IManager.sol";

/**
 * @dev testing open interest before and after
 * asset transfers
 * single side adjustments
 */
contract INTEGRATION_OIFeeTest is IntegrationTestBase {
  address alice = address(0xaa);
  uint accAcc;

  function setUp() public {
    _setupIntegrationTestComplete();
  }

  function testDeploy() public {
    accAcc = accounts.createAccount(alice, IManager(pcrm));
    _depositCash(address(alice), accAcc, 5000e18);
  }
}
