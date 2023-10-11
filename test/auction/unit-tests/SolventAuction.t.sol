// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./DutchAuctionBase.sol";
import {getDefaultAuctionParam} from "../../../scripts/config.sol";

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

  function testStartAuctionPaysFee() public {
    dutchAuction.setSolventAuctionParams(
      IDutchAuction.SolventAuctionParams({
        startingMtMPercentage: 1e18,
        fastAuctionCutoffPercentage: 0.8e18,
        fastAuctionLength: 600,
        slowAuctionLength: 7200,
        liquidatorFeeRate: 0.01e18
      })
    );
    // start auction
    _startDefaultSolventAuction(aliceAcc);

    assertGt(manager.feePaid(), 0);
  }

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
    assertEq(maxProportion / 1e15, 318); // can liquidate 31.8% of portfolio at most
  }

  function testSolventAuctionTerminatedIfMaxProportionIsBid() public {
    _startDefaultSolventAuction(aliceAcc);

    IDutchAuction.SolventAuctionParams memory params = _getDefaultSolventParams();

    vm.warp(block.timestamp + params.fastAuctionLength);

    uint maxProportion = dutchAuction.getMaxProportion(aliceAcc, scenario);

    vm.prank(bob);
    dutchAuction.bid(aliceAcc, bobAcc, maxProportion, 0);

    DutchAuction.Auction memory auction = dutchAuction.getAuction(aliceAcc);
    assertEq(auction.ongoing, false);
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
    assertEq(maxProportion / 1e15, 341); // can liquidate 34.1% of portfolio at most

    // bid on the auction
    vm.prank(bob);
    (uint finalPercentage, uint cashFromBidder, uint cashToBidder) = dutchAuction.bid(aliceAcc, bobAcc, 1e18, 0);

    assertEq(finalPercentage, maxProportion); // bid max
    assertEq(cashToBidder, 0); // bid max
    assertEq(cashFromBidder / 1e18, 92); // 92% of portfolio, price at 270

    // testing that the view returns the correct auction.
    DutchAuction.Auction memory auction = dutchAuction.getAuction(aliceAcc);
    assertEq(auction.ongoing, false); // mark as terminated
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
    (uint finalPercentage, uint cashFromBidder, uint cashToBidder) = dutchAuction.bid(aliceAcc, bobAcc, percentage, 0);

    assertEq(finalPercentage, percentage); // bid max
    assertEq(cashToBidder, 0); // 0 dollar paid from SM
    assertEq(cashFromBidder / 1e18, 27); // 10% of portfolio, price at 270

    // // testing that the view returns the correct auction.
    DutchAuction.Auction memory auction = dutchAuction.getAuction(aliceAcc);
    assertEq(auction.ongoing, true); // start does not automatically un-flag because mocked MM is not updated
    assertEq(auction.insolvent, false);
  }

  function testShouldRevertIfMaxCashExceeded() public {
    _startDefaultSolventAuction(aliceAcc);
    vm.warp(block.timestamp + _getDefaultSolventParams().fastAuctionLength / 2);

    // with 10% to bid, it should be around $27, but bob only want to pay $10
    uint percentage = 0.1e18;
    uint maxCash = 10e18;
    // bid on the auction
    vm.prank(bob);
    vm.expectRevert(IDutchAuction.DA_MaxCashExceeded.selector);
    dutchAuction.bid(aliceAcc, bobAcc, percentage, maxCash);
  }

  function testCannotBidWithNoCash() public {
    _startDefaultSolventAuction(aliceAcc);

    // bid from charlie with no cash
    vm.prank(charlie);
    vm.expectRevert(IDutchAuction.DA_InsufficientCash.selector);
    dutchAuction.bid(aliceAcc, charlieAcc, 1e18, 0);
  }

  function testBidRaceCondition() public {
    _startDefaultSolventAuction(aliceAcc);
    _mintAndDepositCash(charlieAcc, 20_000e18);

    // fast forward to half way through the fast auction
    vm.warp(block.timestamp + _getDefaultSolventParams().fastAuctionLength / 2);

    uint percentage = 0.1e18;

    vm.prank(bob);
    (uint bobPercentage, uint cashFromBob,) = dutchAuction.bid(aliceAcc, bobAcc, percentage, 0);
    // after the first liquidation, mtm should only be slightly reduced (10% reduced, and cash added from bob)
    manager.setMarkToMarket(aliceAcc, 270e18 + int(cashFromBob));

    vm.prank(charlie);
    (uint charliePercentage, uint cashFromCharlie,) = dutchAuction.bid(aliceAcc, charlieAcc, percentage, 0);

    assertEq(cashFromCharlie, cashFromBob, "charlie and bob should pay the same amount");
    assertEq(charliePercentage, bobPercentage, "charlie should receive the same percentage as bob");

    DutchAuction.Auction memory auction = dutchAuction.getAuction(aliceAcc);
    assertEq(auction.percentageLeft, 0.8e18, "percentageLeft should be 0.8");
  }

  function testBidMarkToMarketChange() public {
    _startDefaultSolventAuction(aliceAcc);

    // fast forward to half way through the fast auction, should give me 90% discount
    vm.warp(block.timestamp + _getDefaultSolventParams().fastAuctionLength / 2);

    uint percentage = 0.1e18;

    // mark to market is changed to 1000, now i need to pay 90% of 1000 * 10% = 90
    manager.setMarkToMarket(aliceAcc, 1000e18);

    vm.prank(bob);
    (uint bobPercentage, uint cashFromBob,) = dutchAuction.bid(aliceAcc, bobAcc, percentage, 0);

    assertEq(cashFromBob, 90e18, "cashFromBob should be 90");
    assertEq(bobPercentage, percentage, "bobPercentage should be 10%");
  }

  function testCannotBidWithInvalidPercentage() public {
    _startDefaultSolventAuction(aliceAcc);
    vm.expectRevert(IDutchAuction.DA_InvalidPercentage.selector);
    dutchAuction.bid(aliceAcc, bobAcc, 1.01e18, 0);

    vm.expectRevert(IDutchAuction.DA_InvalidPercentage.selector);
    dutchAuction.bid(aliceAcc, bobAcc, 0, 0);
  }

  function testCannotBidFromNonOwner() public {
    _startDefaultSolventAuction(aliceAcc);
    vm.expectRevert(IDutchAuction.DA_SenderNotOwner.selector);
    dutchAuction.bid(aliceAcc, bobAcc, 1e18, 0);
  }

  function testCanStillBidWhenMMIsZero() public {
    _startDefaultSolventAuction(aliceAcc);

    manager.setMockMargin(aliceAcc, false, scenario, 1e18);

    vm.prank(bob);
    dutchAuction.bid(aliceAcc, bobAcc, 1e18, 0);

    assertEq(dutchAuction.getAuction(aliceAcc).ongoing, false);
  }

  function testCannotBidOnAccountThatBufferMarginIsAboveThreshold() public {
    _startDefaultSolventAuction(aliceAcc);
    // assume maintenance margin to 100, making buffer margin 100 - (200-100)*0.1 = 90
    manager.setMockMargin(aliceAcc, false, scenario, 100e18);
    vm.prank(bob);
    vm.expectRevert(IDutchAuction.DA_AuctionShouldBeTerminated.selector);
    dutchAuction.bid(aliceAcc, bobAcc, 1e18, 0);
  }

  function testCannotGetMaxProportionOnInsolventAuction() public {
    _startDefaultSolventAuction(aliceAcc);
    manager.setMarkToMarket(aliceAcc, -1e18);
    vm.expectRevert(IDutchAuction.DA_SolventAuctionEnded.selector);
    dutchAuction.getMaxProportion(aliceAcc, scenario);
  }

  function testCannotBidOnEndedAuction() public {
    _startDefaultSolventAuction(aliceAcc);
    IDutchAuction.SolventAuctionParams memory params = _getDefaultSolventParams();
    vm.warp(block.timestamp + params.fastAuctionLength + params.slowAuctionLength + 5);

    vm.expectRevert(IDutchAuction.DA_SolventAuctionEnded.selector);
    vm.prank(bob);
    dutchAuction.bid(aliceAcc, bobAcc, 1e18, 0);
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

  function testCannotMarkInsolventIfAccountMMIsOK() public {
    _startDefaultSolventAuction(aliceAcc);

    IDutchAuction.SolventAuctionParams memory params = _getDefaultSolventParams();
    vm.warp(block.timestamp + params.fastAuctionLength + params.slowAuctionLength);

    // assume MM is back above 0
    manager.setMockMargin(aliceAcc, false, scenario, 1e18);
    vm.expectRevert(IDutchAuction.DA_AccountIsAboveMaintenanceMargin.selector);
    dutchAuction.convertToInsolventAuction(aliceAcc);
  }

  function testCanUpdateScenarioID() public {
    _startDefaultSolventAuction(aliceAcc);

    // increment the insolvent auction
    uint newId = 2;
    manager.setMockMargin(aliceAcc, false, newId, -300e18);

    dutchAuction.updateScenarioId(aliceAcc, newId);

    DutchAuction.Auction memory auction = dutchAuction.getAuction(aliceAcc);
    assertEq(auction.scenarioId, newId);
  }

  function testCannotUpdateScenarioIdWithNonOngoingAuction() public {
    vm.expectRevert(IDutchAuction.DA_AuctionNotStarted.selector);
    dutchAuction.updateScenarioId(aliceAcc, 2);
  }

  function testCanUpdateScenarioIDWithHigherIM() public {
    _startDefaultSolventAuction(aliceAcc);

    // increment the insolvent auction
    uint newId = 2;
    manager.setMockMargin(aliceAcc, true, newId, 300e18);

    vm.expectRevert(IDutchAuction.DA_ScenarioIdNotWorse.selector);
    dutchAuction.updateScenarioId(aliceAcc, newId);
  }

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

    // can un-flag if Buffer marin > 0
    // set mm to 100 to make buffer margin > 0
    manager.setMockMargin(aliceAcc, false, scenario, 100e18);
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

  function testCanRevertAuctionWithHighCashReserve() public {
    _startDefaultSolventAuction(aliceAcc);

    // fast forward to half way through the fast auction
    vm.warp(block.timestamp + _getDefaultSolventParams().fastAuctionLength / 2);

    uint percentage = 0.1e18;

    vm.prank(bob);
    (, uint cashFromBob,) = dutchAuction.bid(aliceAcc, bobAcc, percentage, 0);

    // We set the MTM to be lower than the reserved cash
    manager.setMarkToMarket(aliceAcc, int(cashFromBob) - 1);

    vm.prank(charlie);
    vm.expectRevert(IDutchAuction.DA_AuctionShouldBeTerminated.selector);
    dutchAuction.bid(aliceAcc, charlieAcc, percentage, 0);

    vm.expectRevert(IDutchAuction.DA_ReservedCashGreaterThanMtM.selector);
    dutchAuction.convertToInsolventAuction(aliceAcc);

    dutchAuction.terminateAuction(aliceAcc);
  }

  ///@dev test that the second bider's percentage is capped at max liquidatable percentage
  function testPercentageCappedRaceCondition() public {
    address sean = address(0x9999);
    uint seanAcc = subAccounts.createAccount(sean, manager);
    _mintAndDepositCash(aliceAcc, 20_000e18);

    // Make maintenance margin == buffer margin, for easy computation
    dutchAuction.setBufferMarginPercentage(0);

    // setup initial env: MtM = 6000, MM = BM = -10000, discount = 0.2
    manager.setMockMargin(seanAcc, false, scenario, -10000e18);
    manager.setMarkToMarket(seanAcc, 6000e18);
    dutchAuction.startAuction(seanAcc, scenario);

    {
      (, int bufferMargin,) = dutchAuction.getMarginAndMarkToMarket(seanAcc, scenario);
      assertEq(bufferMargin / 1e18, -10000);
    }

    // fast forward to all the way to the end of fast auction
    vm.warp(block.timestamp + _getDefaultSolventParams().fastAuctionLength);

    // discount should be 20%
    assertEq(dutchAuction.getCurrentBidPrice(seanAcc), 4800e18);

    // Alice liquidates 30% of the portfolio
    vm.prank(alice);
    {
      (uint finalPercentage, uint cashFromAlice,) = dutchAuction.bid(seanAcc, aliceAcc, 0.3e18, 0);
      assertEq(finalPercentage, 0.3e18);
      assertEq(cashFromAlice / 1e18, 1440); // 30% of portfolio, price at 4800
    }

    // before Round 2, set MtM and Maintenance margin
    manager.setMarkToMarket(seanAcc, 4200e18 + 1440e18);
    manager.setMockMargin(seanAcc, false, scenario, -7000e18 + 1440e18);

    uint maxF = dutchAuction.getMaxProportion(seanAcc, scenario);
    assertEq(maxF / 1e14, 5366); // 53.66% of CURRENT can be liquidated. (37.5676% of original)

    // check that Bob's max liquidatable percentage is capped
    vm.prank(bob);
    {
      (uint finalPercentage, uint cashFromBob,) = dutchAuction.bid(seanAcc, bobAcc, 0.5e18, 0);
      assertEq(finalPercentage / 1e14, 3756); // capped at 37.5675 of original
      assertEq(cashFromBob / 1e18, 1803); // 37.5675% of portfolio, price at 4800
    }
  }

  function testConvertToInsolventAuction_WithReservedCash() public {
    // If an auction is bid several times (with reserved cash), and MtM (with added cash) < reserved cash
    // It should be terminated and restart as an insolvent auction

    address sean = address(0x9999);
    uint seanAcc = subAccounts.createAccount(sean, manager);
    _mintAndDepositCash(aliceAcc, 20_000e18);

    // Make maintenance margin == buffer margin, for easy computation
    dutchAuction.setBufferMarginPercentage(0);

    // set fast auction cutoff to be 70%
    IDutchAuction.SolventAuctionParams memory params = getDefaultAuctionParam();
    params.fastAuctionCutoffPercentage = 0.7e18;
    dutchAuction.setSolventAuctionParams(params);

    // Auction starts
    manager.setMockMargin(seanAcc, false, scenario, -10000e18);
    manager.setMarkToMarket(seanAcc, 8000e18);
    dutchAuction.startAuction(seanAcc, scenario);

    // Alice liquidate Sean: paying $1200 into reserved funds
    assertEq(dutchAuction.getCurrentBidPrice(seanAcc), 8000e18);

    vm.prank(alice);
    (, uint cashPaid,) = dutchAuction.bid(seanAcc, aliceAcc, 0.2e18, 0);
    assertEq(cashPaid, 1600e18);

    // setup env: MtM = 9600, MM = BM = -10000, discount = 30%, liquidated = 20%
    vm.warp(block.timestamp + params.fastAuctionLength);

    manager.setMockMargin(seanAcc, false, scenario, -10000e18);
    manager.setMarkToMarket(seanAcc, 9600e18);

    int bidPrice = dutchAuction.getCurrentBidPrice(seanAcc);
    assertEq(dutchAuction.getCurrentBidPrice(seanAcc), 7000e18);
    manager.setMarkToMarket(seanAcc, 1000e18);

    // Can restart auction
    dutchAuction.terminateAuction(seanAcc);

    // MtM should now be 1000 - 1600 = -600
    manager.setMarkToMarket(seanAcc, -600e18);
    dutchAuction.startAuction(seanAcc, scenario);

    assertEq(dutchAuction.getCurrentBidPrice(seanAcc), 0);
  }

  function _startDefaultSolventAuction(uint acc) internal {
    // -100 maintenance margin
    manager.setMockMargin(acc, false, scenario, -100e18);

    // mark to market: 300
    manager.setMarkToMarket(acc, 300e18);

    // buffer is -400
    // buffer marin = -100 - 40 = -140

    // start an auction on Alice's account
    dutchAuction.startAuction(acc, scenario);
  }
}
