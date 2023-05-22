// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./DutchAuctionBase.sol";
import "forge-std/console2.sol";
//

contract UNIT_TestInsolventAuction is DutchAuctionBase {
  uint scenario = 1;

  function testStartInsolventAuction() public {
    _startDefaultInsolventAuction(aliceAcc);

    // testing that the view returns the correct auction.
    DutchAuction.Auction memory auction = dutchAuction.getAuction(aliceAcc);

    // log all the auction struct details
    assertEq(auction.insolvent, true);
    assertEq(auction.ongoing, true);
    assertEq(auction.startTime, block.timestamp);

    // getting the current bid price
    int currentBidPrice = dutchAuction.getCurrentBidPrice(aliceAcc);
    assertEq(currentBidPrice, 0); // start with 0
  }

  function testCanBidOnInsolventAuctionWith0Bid() public {
    _startDefaultInsolventAuction(aliceAcc);

    vm.prank(bob);
    (uint finalPercentage, uint cashFromBidder, uint cashToBidder) = dutchAuction.bid(aliceAcc, bobAcc, 1e18);

    // pay 0 and receive 0 extra cash from SM
    assertEq(finalPercentage, 1e18);
    assertEq(cashFromBidder, 0);
    assertEq(cashToBidder, 0);
  }

  function testBidForInsolventAuctionFromSM() public {
    _startDefaultInsolventAuction(aliceAcc);

    // increase step to 1
    _increaseInsolventStep(1, aliceAcc);

    vm.prank(bob);
    // bid 50% of the portfolio
    (uint finalPercentage, uint cashFromBidder, uint cashToBidder) = dutchAuction.bid(aliceAcc, bobAcc, 0.5e18);

    // 1% of 200 * 50% (max value) = 1
    uint expectedTotalPayoutFromSM = 1e18;

    assertEq(finalPercentage, 0.5e18);
    assertEq(cashFromBidder, 0);
    assertEq(cashToBidder, expectedTotalPayoutFromSM);
  }

  function testBidForInsolventAuctionMakesSMInsolvent() public {
    _startDefaultInsolventAuction(aliceAcc);

    // increase step to 5
    _increaseInsolventStep(5, aliceAcc);

    vm.prank(bob);
    // bid 100% of the portfolio
    (uint finalPercentage, uint cashFromBidder, uint cashToBidder) = dutchAuction.bid(aliceAcc, bobAcc, 1e18);

    // 5% of 200 = 10
    uint expectedPayout = 10e18;

    assertEq(finalPercentage, 1e18);
    assertEq(cashFromBidder, 0);
    assertEq(cashToBidder, expectedPayout);

    assertEq(usdcAsset.isSocialized(), true);
  }

  function testIncreaseStepMax() public {
    dutchAuction.setInsolventAuctionParams(IDutchAuction.InsolventAuctionParams({totalSteps: 2, coolDown: 0}));
    _startDefaultInsolventAuction(aliceAcc);

    dutchAuction.continueInsolventAuction(aliceAcc);
    dutchAuction.continueInsolventAuction(aliceAcc);

    vm.expectRevert(IDutchAuction.DA_MaxStepReachedInsolventAuction.selector);
    dutchAuction.continueInsolventAuction(aliceAcc);
  }

  function testCannotSpamIncrementStep() public {
    _startDefaultInsolventAuction(aliceAcc);

    vm.expectRevert(IDutchAuction.DA_InCoolDown.selector);
    dutchAuction.continueInsolventAuction(aliceAcc);
  }

  function testTerminatesInsolventAuction() public {
    _startDefaultInsolventAuction(aliceAcc);

    // set maintenance margin > 0
    manager.setMockMargin(aliceAcc, false, scenario, 100e18);
    // terminate the auction
    dutchAuction.terminateAuction(aliceAcc);
    // check that the auction is terminated
    assertEq(dutchAuction.getAuction(aliceAcc).ongoing, false);
  }

  function _increaseInsolventStep(uint steps, uint acc) internal {
    // increase step to 1
    for (uint i = 0; i < steps; i++) {
      vm.warp(block.timestamp + 5);
      dutchAuction.continueInsolventAuction(acc);
    }
  }

  function _startDefaultInsolventAuction(uint acc) internal {
    // -500 init margin
    manager.setMockMargin(acc, true, scenario, -200e18);

    // -300 maintenance margin
    manager.setMockMargin(acc, false, scenario, -100e18);

    // mark to market: negative!!
    manager.setMarkToMarket(acc, -100e18);

    // start an auction on Alice's account
    dutchAuction.startAuction(acc, scenario);
  }
}
