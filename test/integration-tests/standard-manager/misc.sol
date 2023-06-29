// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import "lyra-utils/encoding/OptionEncoding.sol";

import "../shared/IntegrationTestBase.t.sol";

contract INTEGRATION_SRM_Example is IntegrationTestBase {
  using DecimalMath for uint;

  function setUp() public {
    _setupIntegrationTestComplete();

    // init setup for both accounts
    _depositCash(alice, aliceAcc, DEFAULT_DEPOSIT);
    _depositCash(bob, bobAcc, DEFAULT_DEPOSIT);

    _setSpotPrice("weth", 2000e18, 1e18);
  }

  // example of using the test setup
  function testInitialMargin() public {
    uint64 expiry = uint64(block.timestamp) + 4 weeks;
    uint strike = 2000e18;
    uint96 callId = OptionEncoding.toSubId(expiry, strike, true);

    // set forward price for expiry
    _setForwardPrice("weth", expiry, 2000e18, 1e18);
    // set vol for this expiry, need to be called after setting forward price
    _setDefaultSVIForExpiry("weth", expiry);

    _tradeDefaultCall(callId, 1e18);

    // console2.log("alice im", getAccInitMargin(aliceAcc) / 1e18);
    // console2.log("bob im", getAccInitMargin(bobAcc) / 1e18);
  }

  ///@dev alice go short, bob go long
  function _tradeDefaultCall(uint96 subId, int amount) public {
    int premium = 50e18;
    // alice send call to bob, bob send premium to alice
    _submitTrade(aliceAcc, markets["weth"].option, subId, amount, bobAcc, cash, 0, premium);
  }
}
