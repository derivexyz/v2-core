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

  // test auction starting price and bidding price
  function testAuctionParameter() public {
    _tradeCall();

    // update price to make IM < 0
    vm.warp(block.timestamp + 12 hours);
    _setSpotPriceE18(2200e18);
    _updateJumps();
    vm.warp(block.timestamp + 12 hours);
    _setSpotPriceE18(2500e18);
    _updateJumps();
    uint maxJump = spotJumpOracle.getMaxJump(1 days);
    assertEq(maxJump, 2500); // max jump is 25%

    int im = getAccInitMargin(aliceAcc); // around -$8341
    console2.log("im", im);

    int imrv0 = getAccInitMarginRVZero(aliceAcc); // around -$4973
    console2.log("imrv0", imrv0);

    auction.startAuction(aliceAcc);

    DutchAuction.Auction memory auction = auction.getAuction(aliceAcc);
    console2.log("auction.upper", auction.upperBound);
    // console2.log("auction.lower", lower);
    // (int upper, int lower) = auction.getBounds(aliceAcc);
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
