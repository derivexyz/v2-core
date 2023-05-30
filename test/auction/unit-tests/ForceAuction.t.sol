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

  function testStartForcedSolventAuctionPaysFee() public {
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
    _startForcedSolventAuction(aliceAcc);

    assertEq(manager.feePaid(), 0);
  }

  function testStartForcedInsolventAuctionDoesntPaysFee() public {
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
    _startForcedInsolventAuction(aliceAcc);

    assertEq(manager.feePaid(), 0);
  }

  function _startForcedSolventAuction(uint acc) internal {
    manager.setMockMargin(acc, false, scenario, 100e18);
    manager.setMarkToMarket(acc, 400e18);
    // start an auction on Alice's account
    manager.forceAuction(dutchAuction, acc, scenario);
  }

  function _startForcedInsolventAuction(uint acc) internal {
    manager.setMockMargin(acc, false, scenario, -100e18);
    manager.setMarkToMarket(acc, -400e18);
    // start an auction on Alice's account
    manager.forceAuction(dutchAuction, acc, scenario);
  }
}
