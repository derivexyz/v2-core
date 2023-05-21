// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../DutchAuctionBase.sol";

contract UNIT_TestStartAuction is DutchAuctionBase {

  uint scenario = 1;

  function testCannotGetBidPriceOnNormalAccount() public {
    vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_AuctionNotStarted.selector, aliceAcc));
    dutchAuction.getCurrentBidPrice(aliceAcc);
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

  //  function testStartInsolventAuctionRead() public {
  //    _startDefaultInsolventAuction(aliceAcc);

  //    // testing that the view returns the correct auction.
  //    DutchAuction.Auction memory auction = dutchAuction.getAuction(aliceAcc);

  //    // log all the auction struct details
  //    assertEq(auction.insolvent, true);
  //    assertEq(auction.ongoing, true);
  //    assertEq(auction.startTime, block.timestamp);

  //    (int upperBound, int lowerBound) = dutchAuction.getBounds(aliceAcc);
  //    assertEq(upperBound, -1);
  //    assertEq(lowerBound, -1000e18);

  //    // getting the current bid price
  //    int currentBidPrice = dutchAuction.getCurrentBidPrice(aliceAcc);
  //    assertEq(currentBidPrice, 0);
  //  }

  //  function testCannotStartAuctionOnAccountAboveMargin() public {
  //    vm.expectRevert(IDutchAuction.DA_AccountIsAboveMaintenanceMargin.selector);
  //    dutchAuction.startAuction(aliceAcc);
  //  }

  //  function testStartAuctionAndCheckValues() public {
  //    manager.giveAssets(aliceAcc);
  //    manager.setMaintenanceMarginForPortfolio(-1);

  //    // start an auction on Alice's account
  //    dutchAuction.startAuction(aliceAcc);

  //    // testing that the view returns the correct auction.
  //    DutchAuction.Auction memory auction = dutchAuction.getAuction(aliceAcc);

  //    (int upperBound, int lowerBound) = dutchAuction.getBounds(aliceAcc);
  //    assertEq(auction.lowerBound, lowerBound);
  //    assertEq(auction.upperBound, upperBound);
  //  }

  //  function testCannotStartAuctionAlreadyStarted() public {
  //    _startDefaultSolventAuction(aliceAcc);

  //    // start an auction on Alice's account
  //    vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_AuctionAlreadyStarted.selector, aliceAcc));
  //    dutchAuction.startAuction(aliceAcc);
  //  }

  //  // test that an auction can start as solvent and convert to insolvent
  //  function testConvertToInsolventAuction() public {
  //    _startDefaultSolventAuction(aliceAcc);

  //    // testing that the view returns the correct auction.
  //    DutchAuction.Auction memory auction = dutchAuction.getAuction(aliceAcc);
  //    assertEq(auction.insolvent, false);

  //    // fast forward
  //    vm.warp(block.timestamp + dutchAuctionParameters.lengthOfAuction);
  //    assertEq(dutchAuction.getCurrentBidPrice(aliceAcc), 0);

  //    // mark the auction as insolvent
  //    dutchAuction.convertToInsolventAuction(aliceAcc);

  //    // testing that the view returns the correct auction.
  //    auction = dutchAuction.getAuction(aliceAcc);
  //    assertEq(auction.insolvent, true);

  //    // cannot mark twice
  //    vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_AuctionAlreadyInInsolvencyMode.selector, aliceAcc));
  //    dutchAuction.convertToInsolventAuction(aliceAcc);
  //  }

  //  function testStartAuctionFailingOnGoingAuction() public {
  //    _startDefaultSolventAuction(aliceAcc);

  //    vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_AuctionAlreadyStarted.selector, aliceAcc));
  //    dutchAuction.startAuction(aliceAcc);
  //  }

  //  function testCannotMarkInsolventIfAuctionNotInsolvent() public {
  //    _startDefaultSolventAuction(aliceAcc);

  //    // testing that the view returns the correct auction.
  //    DutchAuction.Auction memory auction = dutchAuction.getAuction(aliceAcc);
  //    assertEq(auction.accountId, aliceAcc);
  //    assertEq(auction.ongoing, true);
  //    assertEq(auction.insolvent, false);

  //    assertGt(dutchAuction.getCurrentBidPrice(aliceAcc), 0);
  //    // start an auction on Alice's account
  //    vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_AuctionNotEnteredInsolvency.selector, aliceAcc));
  //    dutchAuction.convertToInsolventAuction(aliceAcc);
  //  }

  //  function testGetMaxProportionNegativeMargin() public {
  //    // mock MM and IM
  //    manager.giveAssets(aliceAcc);
  //    manager.setMaintenanceMarginForPortfolio(-1);
  //    manager.setInitMarginForPortfolio(-100_000 * 1e18);

  //    // start an auction on Alice's account
  //    dutchAuction.startAuction(aliceAcc);

  //    // getting the max proportion
  //    uint maxProportion = dutchAuction.getMaxProportion(aliceAcc);
  //    assertEq(maxProportion, 1e18); // 100% of the portfolio could be liquidated
  //  }

  //  function testGetMaxProportionPositiveMargin() public {
  //    // mock MM and IM
  //    manager.giveAssets(aliceAcc);
  //    manager.setMaintenanceMarginForPortfolio(-1);
  //    manager.setInitMarginForPortfolio(1000 * 1e18);

  //    // start an auction on Alice's account
  //    dutchAuction.startAuction(aliceAcc);

  //    // getting the max proportion
  //    uint maxProportion = dutchAuction.getMaxProportion(aliceAcc);
  //    assertEq(maxProportion, 1e18); // 100% of the portfolio could be liquidated
  //  }

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

  //  function testCannotStepNonInsolventAuction() public {
  //    _startDefaultSolventAuction(aliceAcc);

  //    // increment the insolvent auction
  //    vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_SolventAuctionCannotIncrement.selector, aliceAcc));
  //    dutchAuction.continueInsolventAuction(aliceAcc);
  //  }

  //  function testTerminatesSolventAuction() public {
  //    _startDefaultSolventAuction(aliceAcc);

  //    // testing that the view returns the correct auction.
  //    DutchAuction.Auction memory auction = dutchAuction.getAuction(aliceAcc);
  //    assertEq(auction.ongoing, true);

  //    // deposit margin => makes IM(rv = 0) > 0
  //    manager.setInitMarginForPortfolioZeroRV(15_000 * 1e18);
  //    // terminate the auction
  //    dutchAuction.terminateAuction(aliceAcc);
  //    // check that the auction is terminated
  //    assertEq(dutchAuction.getAuction(aliceAcc).ongoing, false);
  //  }

  //  function testTerminatesInsolventAuction() public {
  //    _startDefaultInsolventAuction(aliceAcc);

  //    // testing that the view returns the correct auction.
  //    DutchAuction.Auction memory auction = dutchAuction.getAuction(aliceAcc);
  //    assertEq(auction.ongoing, true);

  //    // set maintenance margin > 0
  //    manager.setMaintenanceMarginForPortfolio(5_000 * 1e18);
  //    // terminate the auction
  //    dutchAuction.terminateAuction(aliceAcc);
  //    // check that the auction is terminated
  //    assertEq(dutchAuction.getAuction(aliceAcc).ongoing, false);
  //  }

  //  function testCannotTerminateAuctionIfAccountIsUnderwater() public {
  //    manager.giveAssets(aliceAcc);
  //    manager.setMaintenanceMarginForPortfolio(-1);
  //    manager.setInitMarginForPortfolio(-10000 * 1e18); // 1 million bucks

  //    // start an auction on Alice's account
  //    dutchAuction.startAuction(aliceAcc);

  //    // terminate the auction
  //    vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_AuctionCannotTerminate.selector, aliceAcc));
  //    dutchAuction.terminateAuction(aliceAcc);
  //  }

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

  //  function _startDefaultInsolventAuction(uint acc) internal {
  //    manager.giveAssets(acc);

  //    manager.setMaintenanceMarginForPortfolio(-1);
  //    manager.setInitMarginForPortfolio(-1000 * 1e18); // 1 thousand bucks

  //    manager.setInitMarginForInversedPortfolio(-1); // price drops from -1 => -1000

  //    // start an auction on Alice's account
  //    dutchAuction.startAuction(acc);
  //  }
}
