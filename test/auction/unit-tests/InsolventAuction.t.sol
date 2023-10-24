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
    (uint finalPercentage, uint cashFromBidder, uint cashToBidder) = dutchAuction.bid(aliceAcc, bobAcc, 1e18, 0, 0);

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
    dutchAuction.bid(aliceAcc, bobAcc, 1e18, 0, 0);
  }

  function testBidForInsolventAuctionFromSM() public {
    _startDefaultInsolventAuction(aliceAcc);

    // increase 2% of time
    vm.warp(block.timestamp + 12);

    vm.prank(bob);
    // bid 50% of the portfolio
    (uint finalPercentage, uint cashFromBidder, uint cashToBidder) = dutchAuction.bid(aliceAcc, bobAcc, 0.5e18, 0, 0);

    // 2% of 300 * 50% = 3
    uint expectedTotalPayoutFromSM = 3e18;

    assertEq(finalPercentage, 0.5e18);
    assertEq(cashFromBidder, 0);
    assertEq(cashToBidder, expectedTotalPayoutFromSM);
  }

  function testBidForInsolventAuctionMakesSMInsolvent() public {
    _startDefaultInsolventAuction(aliceAcc);

    // fast forward 50% of auction
    vm.warp(block.timestamp + 5 minutes);

    vm.prank(bob);
    // bid 100% of the portfolio
    (uint finalPercentage, uint cashFromBidder, uint cashToBidder) = dutchAuction.bid(aliceAcc, bobAcc, 1e18, 0, 0);

    // 50% of 300 = 150
    uint expectedPayout = 150e18;

    assertEq(finalPercentage, 1e18);
    assertEq(cashFromBidder, 0);
    assertEq(cashToBidder, expectedPayout);

    assertEq(usdcAsset.isSocialized(), true);

    assertEq(dutchAuction.getIsWithdrawBlocked(), false);
  }

  function testInsolventAuctionBlockWithdraw() public {
    _startDefaultInsolventAuction(aliceAcc);

    assertEq(dutchAuction.getIsWithdrawBlocked(), true);

    vm.warp(block.timestamp + 2 minutes);

    // bid the first half
    vm.prank(bob);
    dutchAuction.bid(aliceAcc, bobAcc, 0.5e18, 0, 0);

    // still blocked
    assertEq(dutchAuction.getIsWithdrawBlocked(), true);

    vm.warp(block.timestamp + 2 minutes);
    vm.prank(bob);
    dutchAuction.bid(aliceAcc, bobAcc, 0.5e18, 0, 0);

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
    assertEq(dutchAuction.getIsWithdrawBlocked(), true);

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

  /**
   * @dev default insolvent auction: 0 -> -300
   */
  function _startDefaultInsolventAuction(uint acc) internal {
    // -300 maintenance margin
    manager.setMockMargin(acc, false, scenario, -300e18);

    // mark to market: negative!!
    manager.setMarkToMarket(acc, -100e18);

    // start an auction on Alice's account
    dutchAuction.startAuction(acc, scenario);
  }
}
