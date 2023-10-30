// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

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
    assertEq(currentBidPrice, -100e18); // start with -MTM
  }

  function testCanBidOnInsolventAuctionWith0Bid() public {
    _startDefaultInsolventAuction(aliceAcc);

    vm.prank(bob);
    (uint finalPercentage, uint cashFromBidder, uint cashToBidder) = dutchAuction.bid(aliceAcc, bobAcc, 1e18, 0, 0);

    assertEq(finalPercentage, 1e18, "finalPercentage");
    assertEq(cashFromBidder, 0);
    // Receive 100 from the auction, as the MTM is -100
    assertEq(cashToBidder, 100e18);
  }

  function testCanBidOnInsolventAuctionWith0BidPositiveMTM() public {
    _startDefaultInsolventAuction(aliceAcc);
    manager.setMarkToMarket(aliceAcc, 100e18);

    vm.prank(bob);
    (uint finalPercentage, uint cashFromBidder, uint cashToBidder) = dutchAuction.bid(aliceAcc, bobAcc, 1e18, 0, 0);

    assertEq(finalPercentage, 1e18, "finalPercentage");
    assertEq(cashFromBidder, 0);
    // Receive 0 from the auction, as the MTM is > 0
    assertEq(cashToBidder, 0);
  }

  function testCanAddALimitToTheCashReceived() public {
    _startDefaultInsolventAuction(aliceAcc);

    vm.startPrank(bob);
    vm.expectRevert(IDutchAuction.DA_CashLimitExceeded.selector);
    dutchAuction.bid(aliceAcc, bobAcc, 1e18, -200e18, 0);

    // This increases the price by -100
    vm.warp(block.timestamp + _getDefaultAuctionParams().insolventAuctionLength / 2);

    vm.expectRevert(IDutchAuction.DA_CashLimitExceeded.selector);
    dutchAuction.bid(aliceAcc, bobAcc, 1e18, -201e18, 0);

    dutchAuction.bid(aliceAcc, bobAcc, 1e18, -200e18, 0);

    vm.stopPrank();
  }

  function testCannotBidOnInsolventAuctionIfAccountUnderwater() public {
    _startDefaultInsolventAuction(aliceAcc);

    vm.prank(bob);
    usdcAsset.withdraw(bobAcc, 19999e18, bob);

    vm.prank(bob);
    vm.expectRevert(IDutchAuction.DA_InsufficientCash.selector);
    dutchAuction.bid(aliceAcc, bobAcc, 1e18, 0, 0);

    vm.prank(bob);
    usdcAsset.withdraw(bobAcc, 1e18, bob);

    vm.prank(bob);
    vm.expectRevert(IDutchAuction.DA_InvalidBidderPortfolio.selector);
    dutchAuction.bid(aliceAcc, bobAcc, 1e18, 0, 0);

    // Can bid successfully with enough collateral
    _mintAndDepositCash(bobAcc, 20000e18);
    vm.prank(bob);
    dutchAuction.bid(aliceAcc, bobAcc, 1e18, 0, 0);
  }

  function testBidForInsolventAuctionFromSM() public {
    _startDefaultInsolventAuction(aliceAcc);

    // increase 2% of time
    vm.warp(block.timestamp + 12);

    vm.prank(bob);
    // bid 50% of the portfolio
    (uint finalPercentage, uint cashFromBidder, uint cashToBidder) = dutchAuction.bid(aliceAcc, bobAcc, 0.5e18, 0, 0);

    // ((0.02 * 200) + 100) * 0.5 = 110
    uint expectedTotalPayoutFromSM = 52e18;

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

    // (50% of 200) + 100 = 200
    uint expectedPayout = 200e18;

    assertEq(finalPercentage, 1e18);
    assertEq(cashFromBidder, 0);
    assertEq(cashToBidder, expectedPayout);

    assertEq(usdcAsset.isSocialized(), true);

    assertEq(dutchAuction.getIsWithdrawBlocked(), false);
  }

  function testInsolventAuctionBlockWithdraw() public {
    dutchAuction.setSMAccount(charlieAcc);

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

    assertEq(dutchAuction.getCurrentBidPrice(aliceAcc), 0);

    // terminate the auction
    dutchAuction.terminateAuction(aliceAcc);
    // check that the auction is terminated
    assertEq(dutchAuction.getAuction(aliceAcc).ongoing, false);
  }

  function testTerminatingAuctionFreeWithdrawLock() public {
    dutchAuction.setSMAccount(charlieAcc);
    _mintAndDepositCash(charlieAcc, 50e18);

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
    _startDefaultInsolventAuction(aliceAcc);
    assertEq(dutchAuction.totalInsolventMM(), 300e18);
    // No sm is set, so withdrawals are not blocked
    assertEq(dutchAuction.getIsWithdrawBlocked(), false);

    _startDefaultInsolventAuction(bobAcc);
    assertEq(dutchAuction.totalInsolventMM(), 600e18);
    assertEq(dutchAuction.getIsWithdrawBlocked(), false);

    dutchAuction.setSMAccount(charlieAcc);
    assertEq(dutchAuction.getIsWithdrawBlocked(), true);

    _mintAndDepositCash(charlieAcc, 599e18);
    assertEq(dutchAuction.getIsWithdrawBlocked(), true);
    _mintAndDepositCash(charlieAcc, 1e18);
    assertEq(dutchAuction.getIsWithdrawBlocked(), false);

    vm.prank(charlie);
    usdcAsset.withdraw(charlieAcc, 600e18, charlie);

    assertEq(dutchAuction.getIsWithdrawBlocked(), true);

    // alice is back above margin, auction terminated
    manager.setMockMargin(aliceAcc, false, scenario, 100e18);
    dutchAuction.terminateAuction(aliceAcc);

    // still blocked because of bob
    assertEq(dutchAuction.getIsWithdrawBlocked(), true);

    manager.setMockMargin(bobAcc, false, scenario, 100e18);
    dutchAuction.terminateAuction(bobAcc);

    // and is cleared once terminated
    assertEq(dutchAuction.getIsWithdrawBlocked(), false);
  }

  /**
   * @dev default insolvent auction: -100 -> -300
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
