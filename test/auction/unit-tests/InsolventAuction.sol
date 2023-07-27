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

  function testCannotBidOnInsolventAuctionIfAccountUnderwater() public {
    _startDefaultInsolventAuction(aliceAcc);

    // bidder bob is also under water
    manager.setMockMargin(bobAcc, false, scenario, -300e18);

    vm.prank(bob);

    vm.expectRevert(IDutchAuction.DA_BidderInsolvent.selector);
    (uint finalPercentage, uint cashFromBidder, uint cashToBidder) = dutchAuction.bid(aliceAcc, bobAcc, 1e18);
  }

  function testBidForInsolventAuctionFromSM() public {
    _startDefaultInsolventAuction(aliceAcc);

    // increase step to 1
    _increaseInsolventStep(1, aliceAcc);

    vm.prank(bob);
    // bid 50% of the portfolio
    (uint finalPercentage, uint cashFromBidder, uint cashToBidder) = dutchAuction.bid(aliceAcc, bobAcc, 0.5e18);

    // 1% of 384 * 50% = 19.2
    uint expectedTotalPayoutFromSM = 1.92e18;

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

    // 5% of 384 = 19.2
    uint expectedPayout = 19.2e18;

    assertEq(finalPercentage, 1e18);
    assertEq(cashFromBidder, 0);
    assertEq(cashToBidder, expectedPayout);

    assertEq(usdcAsset.isSocialized(), true);
  }

  function testCannotIncreaseStepAfterTerminate() public {
    _startDefaultInsolventAuction(aliceAcc);

    // increase step to 5
    _increaseInsolventStep(5, aliceAcc);

    // bid 100% of the portfolio
    vm.prank(bob);
    dutchAuction.bid(aliceAcc, bobAcc, 1e18);

    vm.expectRevert(IDutchAuction.DA_NotOngoingAuction.selector);
    dutchAuction.continueInsolventAuction(aliceAcc);
  }

  function testIncreaseStepMax() public {
    dutchAuction.setInsolventAuctionParams(
      IDutchAuction.InsolventAuctionParams({totalSteps: 2, coolDown: 0, bufferMarginScalar: 1e18})
    );
    _startDefaultInsolventAuction(aliceAcc);

    vm.warp(block.timestamp + 1);
    dutchAuction.continueInsolventAuction(aliceAcc);
    vm.warp(block.timestamp + 1);
    dutchAuction.continueInsolventAuction(aliceAcc);

    vm.warp(block.timestamp + 1);
    vm.expectRevert(IDutchAuction.DA_MaxStepReachedInsolventAuction.selector);
    dutchAuction.continueInsolventAuction(aliceAcc);
  }

  function testCannotSpamIncrementStep() public {
    _startDefaultInsolventAuction(aliceAcc);

    vm.expectRevert(IDutchAuction.DA_InCoolDown.selector);
    dutchAuction.continueInsolventAuction(aliceAcc);

    // cannot spam even if "coolDown" config is not set
    dutchAuction.setInsolventAuctionParams(
      IDutchAuction.InsolventAuctionParams({totalSteps: 0, coolDown: 0, bufferMarginScalar: 1e18})
    );
    vm.expectRevert(IDutchAuction.DA_InCoolDown.selector);
    dutchAuction.continueInsolventAuction(aliceAcc);
  }

  function testInsolventAuctionBelowThresholdBlockWithdraw() public {
    dutchAuction.setWithdrawBlockThreshold(-50e18);
    _startDefaultInsolventAuction(aliceAcc);

    assertEq(dutchAuction.getIsWithdrawBlocked(), true);
  }

  function testInsolventAuctionsAboveThresholdDoesNotBlockWithdraw() public {
    dutchAuction.setWithdrawBlockThreshold(-500e18);

    _startDefaultInsolventAuction(aliceAcc);
    assertEq(dutchAuction.getIsWithdrawBlocked(), false);
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

  function testTerminatingAuctionFreeWithdrawLock() public {
    dutchAuction.setWithdrawBlockThreshold(-50e18);
    _startDefaultInsolventAuction(aliceAcc);
    // lock withdraw

    // set maintenance margin > 0
    manager.setMockMargin(aliceAcc, false, scenario, 100e18);
    // terminate the auction
    dutchAuction.terminateAuction(aliceAcc);

    assertEq(dutchAuction.getIsWithdrawBlocked(), false);
  }

  function testTerminatingAuctionDoesNotFreeLockIfOthersOutstanding() public {
    dutchAuction.setWithdrawBlockThreshold(-50e18);
    _startDefaultInsolventAuction(aliceAcc);
    _startDefaultInsolventAuction(bobAcc);

    // alice is back above margin, auction terminated
    manager.setMockMargin(aliceAcc, false, scenario, 100e18);
    dutchAuction.terminateAuction(aliceAcc);

    // still blocked because of bob
    assertEq(dutchAuction.getIsWithdrawBlocked(), true);
  }

  function _startDefaultInsolventAuction(uint acc) internal {
    // -300 maintenance margin
    manager.setMockMargin(acc, false, scenario, -300e18);

    // mark to market: negative!!
    manager.setMarkToMarket(acc, -100e18);

    // buffer is -200
    // (default) buffer margin is -300 - 20 = -320
    // lowest bid is buffer margin * 1.2 = -384

    // start an auction on Alice's account
    dutchAuction.startAuction(acc, scenario);
  }
}
