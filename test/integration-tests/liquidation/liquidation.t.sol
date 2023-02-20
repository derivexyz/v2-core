// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../shared/IntegrationTestBase.sol";
import "src/interfaces/IManager.sol";
import "src/libraries/OptionEncoding.sol";

/**
 * @dev testing liquidation process
 */
contract INTEGRATION_Liquidation is IntegrationTestBase {
  // value used for test
  uint constant initCash = 5000e18;
  int constant amountOfContracts = 10e18;
  uint constant strike = 2000e18;

  uint96 callId;
  uint96 putId;

  // expiry = 7 days
  uint expiry;

  function setUp() public {
    _setupIntegrationTestComplete();

    // init setup for both accounts
    _depositCash(alice, aliceAcc, initCash);
    _depositCash(bob, bobAcc, initCash);

    expiry = block.timestamp + 7 days;

    callId = OptionEncoding.toSubId(expiry, strike, true);
    putId = OptionEncoding.toSubId(expiry, strike, false);
  }

  // only settle alice's account at expiry
  function testLiquidationIMLowerThan0() public {
    _tradeCall();

    // update price to make IM < 0
    _setSpotPriceE18(3000e18);

    int im = getAccInitMargin(aliceAcc); // around -$11140
    assertTrue(im < 0);

    int imrv0 = getAccInitMarginRVZero(aliceAcc); // around -$11140
    console2.log("imrv0", imrv0);

    auction.startAuction(aliceAcc);
    DutchAuction.Auction memory auction = auction.getAuction(aliceAcc);
    console2.log("auction", auction.upperBound);
  }

  ///@dev alice go short, bob go long
  function _tradeCall() public {
    int premium = 2250e18;
    // alice send call to bob, bob send premium to alice
    _submitTrade(aliceAcc, option, callId, amountOfContracts, bobAcc, cash, 0, premium);
  }

  function _tradePut() public {
    int premium = 1750e18;
    // alice send put to bob, bob send premium to alice
    _submitTrade(aliceAcc, option, putId, amountOfContracts, bobAcc, cash, 0, premium);
  }
}
