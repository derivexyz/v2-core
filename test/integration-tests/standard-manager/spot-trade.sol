// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import "lyra-utils/encoding/OptionEncoding.sol";

import "../shared/IntegrationTestBase.t.sol";

contract INTEGRATION_SRM_BaseAsset is IntegrationTestBase {
  using DecimalMath for uint;

  function setUp() public {
    _setupIntegrationTestComplete();

    // add cash into the system
    _depositCash(alice, aliceAcc, DEFAULT_DEPOSIT);

    _setSpotPrice("wbtc", 25000e18, 1e18);
    _depositBase("wbtc", bob, bobAcc, 1e18);
  }

  // example of using the test setup
  function testCanBorrowAgainstBase() public {
    srm.setBorrowingEnabled(true);
    srm.setBaseAssetMarginFactor(markets["wbtc"].id, 0.5e18, 1e18);

    _withdrawCash(bob, bobAcc, DEFAULT_DEPOSIT);

    assertEq(getCashBalance(bobAcc), -int(DEFAULT_DEPOSIT));
  }
}
