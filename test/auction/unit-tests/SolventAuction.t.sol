// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./DutchAuctionBase.sol";

contract UNIT_TestSolventAuction is DutchAuctionBase {
  uint scenario = 1;

  function testCannotGetBidPriceOnNormalAccount() public {
    vm.expectRevert(IDutchAuction.DA_AuctionNotStarted.selector);
    dutchAuction.getCurrentBidPrice(aliceAcc);
  }

  function testCannotCallTerminateOnNonExistentAuction() public {
    vm.expectRevert(IDutchAuction.DA_NotOngoingAuction.selector);
    dutchAuction.getAuctionStatus(aliceAcc);
  }

  /////////////////////////
  // Start Auction Tests //
  /////////////////////////

  function testStartSolventAuction() public {
    _startDefaultSolventAuction(aliceAcc);

    // testing that the view returns the correct auction.
    DutchAuction.Auction memory auction = dutchAuction.getAuction(aliceAcc);

    // log all the auction struct details
    assertEq(auction.insolvent, false);
    assertEq(auction.ongoing, true);
    assertEq(auction.startTime, block.timestamp);

    // getting the current bid price
    int currentBidPrice = dutchAuction.getCurrentBidPrice(aliceAcc);
    assertEq(currentBidPrice, 300e18); // 100% of mark to market

    uint maxProportion = dutchAuction.getMaxProportion(aliceAcc, scenario);
    assertEq(maxProportion, 0.4e18); // can liquidate 40% of portfolio at most
  }

  function testCannotAuctionOnSolventAccount() public {
    vm.expectRevert(IDutchAuction.DA_AccountIsAboveMaintenanceMargin.selector);
    dutchAuction.startAuction(aliceAcc, scenario);
  }

  function testCannotRestartAuctions() public {
    _startDefaultSolventAuction(aliceAcc);

    vm.expectRevert(IDutchAuction.DA_AuctionAlreadyStarted.selector);
    dutchAuction.startAuction(aliceAcc, scenario);
  }

  function testCanBidWithMaxPercentage() public {
    _startDefaultSolventAuction(aliceAcc);

    // fast forward to half way through the fast auction
    vm.warp(block.timestamp + _getDefaultSolventParams().fastAuctionLength / 2);

    int currentBidPrice = dutchAuction.getCurrentBidPrice(aliceAcc);
    assertEq(currentBidPrice, 270e18); // 90% of mark to market

    uint maxProportion = dutchAuction.getMaxProportion(aliceAcc, scenario);
    assertEq(maxProportion / 1e15, 425); // can liquidate 42.5% of portfolio at most

    // bid on the auction
    vm.prank(bob);
    (uint finalPercentage, uint cashFromBidder, uint cashToBidder) = dutchAuction.bid(aliceAcc, bobAcc, 1e18);

    assertEq(finalPercentage, maxProportion); // bid max
    assertEq(cashToBidder, 0); // bid max
    assertEq(cashFromBidder / 1e18, 114); // 42.5% of portfolio, price at 270

    // // testing that the view returns the correct auction.
    DutchAuction.Auction memory auction = dutchAuction.getAuction(aliceAcc);
    assertEq(auction.ongoing, true); // start does not automatically un-flag because mocked MM is not updated
    assertEq(auction.insolvent, false);
  }

  function testCanBidWithLowerPercentage() public {
    _startDefaultSolventAuction(aliceAcc);

    // fast forward to half way through the fast auction
    vm.warp(block.timestamp + _getDefaultSolventParams().fastAuctionLength / 2);

    // bidder can liquidate 42.5% of portfolio at most
    uint percentage = 0.1e18;
    // bid on the auction
    vm.prank(bob);
    (uint finalPercentage, uint cashFromBidder, uint cashToBidder) = dutchAuction.bid(aliceAcc, bobAcc, percentage);

    assertEq(finalPercentage, percentage); // bid max
    assertEq(cashToBidder, 0); // 0 dollar paid from SM
    assertEq(cashFromBidder / 1e18, 27); // 10% of portfolio, price at 270

    // // testing that the view returns the correct auction.
    DutchAuction.Auction memory auction = dutchAuction.getAuction(aliceAcc);
    assertEq(auction.ongoing, true); // start does not automatically un-flag because mocked MM is not updated
    assertEq(auction.insolvent, false);
  }

  function testBidRaceCondition() public {
    _startDefaultSolventAuction(aliceAcc);

    // fast forward to half way through the fast auction
    vm.warp(block.timestamp + _getDefaultSolventParams().fastAuctionLength / 2);

    uint percentage = 0.1e18;

    vm.prank(bob);
    (uint bobPercentage, uint cashFromBob,) = dutchAuction.bid(aliceAcc, bobAcc, percentage);
    vm.prank(charlie);
    (uint charliePercentage, uint cashFromCharlie,) = dutchAuction.bid(aliceAcc, charlieAcc, percentage);

    assertEq(cashFromCharlie, cashFromBob); // they should pay the same amount
    assertEq(charliePercentage, bobPercentage);

    DutchAuction.Auction memory auction = dutchAuction.getAuction(aliceAcc);
    assertEq(auction.percentageLeft, 0.8e18);
  }

  function testBidMarkToMarketChange() public {
    _startDefaultSolventAuction(aliceAcc);

    // fast forward to half way through the fast auction, should give me 90% discount
    vm.warp(block.timestamp + _getDefaultSolventParams().fastAuctionLength / 2);

    uint percentage = 0.1e18;

    // mark to market is changed to 1000, now i need to pay 90% of 1000 * 10% = 90
    manager.setMarkToMarket(aliceAcc, 1000e18);

    vm.prank(bob);
    (uint bobPercentage, uint cashFromBob,) = dutchAuction.bid(aliceAcc, bobAcc, percentage);

    assertEq(cashFromBob, 90e18);
    assertEq(bobPercentage, percentage);
  }

  function testCannotBidWithInvalidPercentage() public {
    _startDefaultSolventAuction(aliceAcc);
    vm.expectRevert(IDutchAuction.DA_InvalidPercentage.selector);
    dutchAuction.bid(aliceAcc, bobAcc, 1.01e18);

    vm.expectRevert(IDutchAuction.DA_InvalidPercentage.selector);
    dutchAuction.bid(aliceAcc, bobAcc, 0);
  }

  function testCannotBidFromNonOwner() public {
    _startDefaultSolventAuction(aliceAcc);
    vm.expectRevert(IDutchAuction.DA_SenderNotOwner.selector);
    dutchAuction.bid(aliceAcc, bobAcc, 1e18);
  }

  function testCannotBidOnSolventAccount() public {
    _startDefaultSolventAuction(aliceAcc);
    // assume initial margin is back above threshold
    manager.setMockMargin(aliceAcc, true, 1e18);
    vm.prank(bob);
    vm.expectRevert(IDutchAuction.DA_AuctionShouldBeTerminated.selector);
    dutchAuction.bid(aliceAcc, bobAcc, 1e18);
  }

  function testCannotBidOnEndedAuction() public {
    _startDefaultSolventAuction(aliceAcc);
    IDutchAuction.SolventAuctionParams memory params = _getDefaultSolventParams();
    vm.warp(block.timestamp + params.fastAuctionLength + params.slowAuctionLength + 5);

    vm.expectRevert(IDutchAuction.DA_SolventAuctionEnded.selector);
    vm.prank(bob);
    dutchAuction.bid(aliceAcc, bobAcc, 1e18);
  }

  //  test that an auction can start as solvent and convert to insolvent
  function testConvertToInsolventAuction() public {
    _startDefaultSolventAuction(aliceAcc);

    IDutchAuction.SolventAuctionParams memory params = _getDefaultSolventParams();

    // testing that the view returns the correct auction.
    DutchAuction.Auction memory auction = dutchAuction.getAuction(aliceAcc);
    assertEq(auction.insolvent, false);

    // fast forward till end of auction
    vm.warp(block.timestamp + params.fastAuctionLength + params.slowAuctionLength);
    assertEq(dutchAuction.getCurrentBidPrice(aliceAcc), 0);

    // convert the auction to insolvent auction
    dutchAuction.convertToInsolventAuction(aliceAcc);

    // testing that the view returns the correct auction.
    auction = dutchAuction.getAuction(aliceAcc);
    assertEq(auction.insolvent, true);

    // cannot mark twice
    vm.expectRevert(IDutchAuction.DA_AuctionAlreadyInInsolvencyMode.selector);
    dutchAuction.convertToInsolventAuction(aliceAcc);
  }

  function testCannotMarkInsolventIfAuctionNotInsolvent() public {
    _startDefaultSolventAuction(aliceAcc);

    // testing that the view returns the correct auction.
    DutchAuction.Auction memory auction = dutchAuction.getAuction(aliceAcc);
    assertEq(auction.accountId, aliceAcc);
    assertEq(auction.ongoing, true);
    assertEq(auction.insolvent, false);

    assertGt(dutchAuction.getCurrentBidPrice(aliceAcc), 0);
    // start an auction on Alice's account
    vm.expectRevert(IDutchAuction.DA_OngoingSolventAuction.selector);
    dutchAuction.convertToInsolventAuction(aliceAcc);
  }

  //  function testStartInsolventAuctionAndIncrement() public {
  //    manager.giveAssets(aliceAcc);
  //    manager.setMaintenanceMarginForPortfolio(-1);
  //    manager.setInitMarginForPortfolio(-1000_000 * 1e18); // 1 million bucks underwater
  //    manager.setInitMarginForInversedPortfolio(0); // price drops from 0

  //    // start an auction on Alice's account
  //    dutchAuction.startAuction(aliceAcc);

  //    // testing that the view returns the correct auction.
  //    DutchAuction.Auction memory auction = dutchAuction.getAuction(aliceAcc);
  //    assertEq(auction.insolvent, true);

  //    // getting the current bid price
  //    int currentBidPrice = dutchAuction.getCurrentBidPrice(aliceAcc);
  //    assertEq(currentBidPrice, 0); // starts at 0 as insolvent

  //    // increment the insolvent auction
  //    dutchAuction.continueInsolventAuction(aliceAcc);
  //    // get the current step
  //    uint currentStep = dutchAuction.getAuction(aliceAcc).stepInsolvent;
  //    assertEq(currentStep, 1);
  //  }

  function testCannotStepNonInsolventAuction() public {
    _startDefaultSolventAuction(aliceAcc);

    // increment the insolvent auction
    vm.expectRevert(IDutchAuction.DA_SolventAuctionCannotIncrement.selector);
    dutchAuction.continueInsolventAuction(aliceAcc);
  }

  function testTerminatesSolventAuction() public {
    _startDefaultSolventAuction(aliceAcc);

    // testing that the view returns the correct auction.
    DutchAuction.Auction memory auction = dutchAuction.getAuction(aliceAcc);
    assertEq(auction.ongoing, true);

    // can un-flag if IM > 0
    manager.setMockMargin(aliceAcc, true, 1e18);
    // terminate the auction
    dutchAuction.terminateAuction(aliceAcc);
    // check that the auction is terminated
    assertEq(dutchAuction.getAuction(aliceAcc).ongoing, false);
  }

  function testCannotTerminateUsualAuction() public {
    _startDefaultSolventAuction(aliceAcc);

    vm.expectRevert(IDutchAuction.DA_AuctionCannotTerminate.selector);
    // terminate the auction
    dutchAuction.terminateAuction(aliceAcc);
  }

  function _startDefaultSolventAuction(uint acc) internal {
    // -200 init margin
    manager.setMockMargin(acc, true, -200e18);

    // -100 maintenance margin
    manager.setMockMargin(acc, false, -100e18);

    // mark to market: 300
    manager.setMarkToMarket(acc, 300e18);

    // start an auction on Alice's account
    dutchAuction.startAuction(acc, scenario);
  }
}
