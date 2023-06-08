// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./DutchAuctionBase.sol";

contract UNIT_TestForceAuction is DutchAuctionBase {
  function testCanStartForceAuctionByManager() public {
    vm.prank(address(manager));
    dutchAuction.startForcedAuction(aliceAcc, 1);
  }

  function testCannotStartFromNonManager() public {
    vm.expectRevert(IDutchAuction.DA_OnlyManager.selector);
    vm.prank(address(0xbb));
    dutchAuction.startForcedAuction(aliceAcc, 1);
  }

  function testForceAuctionTakesNoFee() public {
    // enable fees
    IDutchAuction.SolventAuctionParams memory params = _getDefaultSolventParams();
    params.liquidatorFeeRate = 0.1e18;
    dutchAuction.setSolventAuctionParams(params);

    // mock mtm > 0
    manager.setMarkToMarket(aliceAcc, 100e18);

    vm.prank(address(manager));
    dutchAuction.startForcedAuction(aliceAcc, 1);

    // assert no fee charged
    int fee = subAccounts.getBalance(sm.accountId(), usdcAsset, 0);
    assertEq(fee, 0);
  }

  function testCannotConvertToInsolventAuctionIfMMAboveZero() public {
    manager.setMarkToMarket(aliceAcc, 100e18);

    // start solvent auction
    vm.prank(address(manager));
    dutchAuction.startForcedAuction(aliceAcc, 1);

    // time passed, and no one bids
    vm.warp(block.timestamp + 2 days);

    // mm is still > 0
    manager.setMockMargin(aliceAcc, false, 1, 100e18);
    vm.expectRevert(IDutchAuction.DA_AccountIsAboveMaintenanceMargin.selector);
    dutchAuction.convertToInsolventAuction(aliceAcc);
  }

  function testCannotContinueInsolventAuctionIfMMAboveZero() public {
    manager.setMarkToMarket(aliceAcc, 100e18);

    // start solvent auction
    vm.prank(address(manager));
    dutchAuction.startForcedAuction(aliceAcc, 1);

    // time passed, and no one bids
    vm.warp(block.timestamp + 2 days);
    // convert to insolvent auction, when mm is slightly < 0
    manager.setMockMargin(aliceAcc, false, 1, -1e18);
    dutchAuction.convertToInsolventAuction(aliceAcc);

    vm.warp(block.timestamp + 1 minutes);
    manager.setMockMargin(aliceAcc, false, 1, 0);
    vm.expectRevert(IDutchAuction.DA_CannotStepSolventForcedAuction.selector);
    dutchAuction.continueInsolventAuction(aliceAcc);
  }

  function testCanBidOnForcedSolventAuction() public {
    manager.setMarkToMarket(aliceAcc, 100e18);
    vm.prank(address(manager));
    dutchAuction.startForcedAuction(aliceAcc, 1);

    vm.warp(block.timestamp + 5 minutes); // half way through fast auction, 90% discount

    vm.prank(bob);
    (uint finalPercentage, uint cashFromBidder, uint cashToBidder) = dutchAuction.bid(aliceAcc, bobAcc, 1e18);
    assertEq(finalPercentage, 1e18);
    assertEq(cashFromBidder, 90e18);
    assertEq(cashToBidder, 0);
  }

  function testCanBidOnForcedInSolventAuction() public {
    uint scenario = 1;
    manager.setMockMargin(aliceAcc, false, scenario, -300e18);
    manager.setMarkToMarket(aliceAcc, -100e18);

    vm.prank(address(manager));
    dutchAuction.startForcedAuction(aliceAcc, scenario);

    // 50% of the total steps passed
    _increaseInsolventStep(50, aliceAcc);

    IDutchAuction.InsolventAuctionParams memory params = _getDefaultInsolventParams();
    (, int bufferMargin,) = dutchAuction.getMarginAndMarkToMarket(aliceAcc, scenario);
    uint maxPayout = uint(-(bufferMargin * params.bufferMarginScalar / 1e18));

    vm.prank(bob);
    (uint finalPercentage, uint cashFromBidder, uint cashToBidder) = dutchAuction.bid(aliceAcc, bobAcc, 1e18);

    assertEq(finalPercentage, 1e18);
    assertEq(cashFromBidder, 0);
    assertEq(cashToBidder, maxPayout / 2);
  }
}
