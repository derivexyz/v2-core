// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "lyra-utils/encoding/OptionEncoding.sol";

import "../shared/IntegrationTestBase.sol";
import "src/interfaces/IManager.sol";

/**
 * @dev testing some properties of PCRM
 */
contract INTEGRATION_PCRMInvariants is IntegrationTestBase {
  // value used for test
  int constant amountOfContracts = 10e18;
  uint constant strike = 2000e18;

  uint96 callId;

  // expiry = 7 days
  uint expiry;

  function setUp() public {
    _setupIntegrationTestComplete();

    // init setup for both accounts
    _depositCash(alice, aliceAcc, DEFAULT_DEPOSIT);
    _depositCash(bob, bobAcc, DEFAULT_DEPOSIT);

    expiry = block.timestamp + 7 days;

    callId = OptionEncoding.toSubId(expiry, strike, true);
  }

  // test auction starting price and bidding price
  function testFuzzIMAndMM(uint spot_) public {
    int spot = int(spot_); // wrap into int here, specifying int as input will have too many invalid inputs

    vm.assume(spot < 10000e18);
    vm.assume(spot > 1e18);

    _tradeCall();

    _setSpotPriceE18(spot);
    _updateJumps();

    int im = getAccInitMargin(aliceAcc);
    int imNoJump = getAccInitMarginRVZero(aliceAcc);
    int mm = getAccMaintenanceMargin(aliceAcc);

    assertGt(imNoJump, im);

    assertGt(mm, im);
  }

  ///@dev alice go short, bob go long
  function _tradeCall() public {
    int premium = 2250e18;
    // alice send call to bob, bob send premium to alice
    _submitTrade(aliceAcc, option, callId, amountOfContracts, bobAcc, cash, 0, premium);
  }
}
