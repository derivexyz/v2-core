// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "lyra-utils/encoding/OptionEncoding.sol";

import "../shared/IntegrationTestBase.sol";
import {IManager} from "src/interfaces/IManager.sol";

/**
 * @dev testing liquidation process
 */
contract INTEGRATION_Liquidation is IntegrationTestBase {
  // value used for test
  int constant amountOfContracts = 10e18;
  uint constant strike = 2000e18;

  uint96 callId;
  uint96 putId;

  // expiry = 7 days
  uint expiry;

  function setUp() public {
    _setupIntegrationTestComplete();

    // init setup for both accounts
    _depositCash(alice, aliceAcc, DEFAULT_DEPOSIT);
    _depositCash(bob, bobAcc, DEFAULT_DEPOSIT);

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

    // IM is around -$8341
    assertEq(getAccInitMargin(aliceAcc) / 1e18, -8391);
    // IM(RV=0) is around -$4973
    assertEq(getAccInitMarginRVZero(aliceAcc) / 1e18, -4973);

    // can start this auction
    auction.startAuction(aliceAcc);

    // can terminate auction if IM (RV = 0) > 0
    _setSpotPriceE18(2040e18);
    assertGt(getAccInitMarginRVZero(aliceAcc), 0);

    // IM is still < 0
    _updateJumps();
    assertLt(getAccInitMargin(aliceAcc), 0);

    auction.terminateAuction(aliceAcc);
    DutchAuction.Auction memory auctionInfo = auction.getAuction(aliceAcc);
    assertEq(auctionInfo.ongoing, false);

    // cannot start auction again
    vm.expectRevert(IDutchAuction.DA_AccountIsAboveMaintenanceMargin.selector);
    auction.startAuction(aliceAcc);
  }

  function testFuzzAuctionCannotRestartAfterTermination(uint newSpot_) public {
    int newSpot = int(newSpot_); // wrap into int here, specifying int as input will have too many invalid inputs
    vm.assume(newSpot > 1000e18);
    vm.assume(newSpot < 2100e18); // price where it got mark as liquidatable

    // as long as an auction is terminate-able when price is back to {newSpot}
    // it cannot be restart immediate after termination

    // alice is short 10 calls
    _tradeCall();

    // update price to make IM < 0
    vm.warp(block.timestamp + 12 hours);
    _setSpotPriceE18(2500e18);
    _updateJumps();

    // account is liquidatable at this point
    auction.startAuction(aliceAcc);

    // can terminate auction if IM (RV = 0) > 0
    _setSpotPriceE18(newSpot);

    // if account IM(rv) > 0, it can be terminated
    if (getAccInitMarginRVZero(aliceAcc) > 0) {
      // if it's terminate-able, terminate and cannot restart
      auction.terminateAuction(aliceAcc);

      vm.expectRevert(IDutchAuction.DA_AccountIsAboveMaintenanceMargin.selector);
      auction.startAuction(aliceAcc);
    } else {
      // cannot terminate
      vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_AuctionCannotTerminate.selector, aliceAcc));
      auction.terminateAuction(aliceAcc);
    }
  }

  ///@dev alice go short, bob go long
  function _tradeCall() public {
    int premium = 2250e18;
    // alice send call to bob, bob send premium to alice
    _submitTrade(aliceAcc, option, callId, amountOfContracts, bobAcc, cash, 0, premium);
  }
}
