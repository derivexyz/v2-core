// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../DutchAuctionBase.sol";
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

  //
  //  function testStartInsolventAuction() public {
  //    createDefaultInsolventAuction(aliceAcc);
  //    DutchAuction.Auction memory auction = dutchAuction.getAuction(aliceAcc);
  //    assertEq(auction.insolvent, true); // start as insolvent from the very beginning
  //
  //    // starts with 0 bid
  //    assertEq(dutchAuction.getCurrentBidPrice(aliceAcc), 0);
  //
  //    // increment the insolvent auction
  //    // 1 of 200 steps
  //    dutchAuction.continueInsolventAuction(aliceAcc);
  //    assertEq(dutchAuction.getCurrentBidPrice(aliceAcc), -5000e18);
  //
  //    // 2 of 200 steps
  //    dutchAuction.continueInsolventAuction(aliceAcc);
  //    assertEq(dutchAuction.getCurrentBidPrice(aliceAcc), -10_000e18);
  //  }
  //
  //  function testBidForInsolventAuctionFromSM() public {
  //    createDefaultInsolventAuction(aliceAcc);
  //
  //    // 2 of 200 steps
  //    dutchAuction.continueInsolventAuction(aliceAcc);
  //    dutchAuction.continueInsolventAuction(aliceAcc);
  //
  //    int expectedTotalPayoutFromSM = 10_000e18;
  //
  //    // if sm has enough balance
  //    sm.mockBalance(expectedTotalPayoutFromSM);
  //    usdcAsset.deposit(sm.accountId(), uint(expectedTotalPayoutFromSM));
  //
  //    assertEq(dutchAuction.getCurrentBidPrice(aliceAcc), -expectedTotalPayoutFromSM);
  //
  //    int cashBefore = account.getBalance(bobAcc, usdcAsset, 0);
  //
  //    vm.prank(bob);
  //    dutchAuction.bid(aliceAcc, bobAcc, 0.2e18); // bid for 20%
  //
  //    int cashAfter = account.getBalance(bobAcc, usdcAsset, 0);
  //
  //    assertEq(cashAfter - cashBefore, expectedTotalPayoutFromSM * 2 / 10);
  //    assertEq(usdcAsset.isSocialized(), false);
  //  }
  //
  //  function testBidForInsolventAuctionMakesSMInsolvent() public {
  //    createDefaultInsolventAuction(aliceAcc);
  //
  //    // 2 of 200 steps
  //    dutchAuction.continueInsolventAuction(aliceAcc);
  //    dutchAuction.continueInsolventAuction(aliceAcc);
  //
  //    int expectedTotalPayoutFromSM = 10_000e18;
  //
  //    // if sm doesn't have enough balance
  //    sm.mockBalance(1000e18);
  //    usdcAsset.deposit(sm.accountId(), uint(1000e18));
  //
  //    int cashBefore = account.getBalance(bobAcc, usdcAsset, 0);
  //
  //    vm.prank(bob);
  //    dutchAuction.bid(aliceAcc, bobAcc, 1e18); // bid for 100%
  //
  //    int cashAfter = account.getBalance(bobAcc, usdcAsset, 0);
  //    assertEq(cashAfter - cashBefore, expectedTotalPayoutFromSM);
  //
  //    assertEq(usdcAsset.isSocialized(), true);
  //  }
  //
  //  function testIncreaseStepMax() public {
  //    dutchAuction.setSolventAuctionParams(
  //      IDutchAuction.SolventAuctionParams({
  //        stepInterval: 2,
  //        lengthOfAuction: 2,
  //        liquidatorFeeRate: 0.05e18,
  //        secBetweenSteps: 0 // cool down is 0
  //      })
  //    );
  //    createDefaultInsolventAuction(aliceAcc);
  //
  //    dutchAuction.continueInsolventAuction(aliceAcc);
  //
  //    vm.expectRevert(IDutchAuction.DA_MaxStepReachedInsolventAuction.selector);
  //    dutchAuction.continueInsolventAuction(aliceAcc);
  //  }
  //
  //  function testCannotSpamIncrementStep() public {
  //    // change parameters to add cool down
  //    dutchAuction.setSolventAuctionParams(
  //      IDutchAuction.SolventAuctionParams({
  //        stepInterval: 2,
  //        lengthOfAuction: 200,
  //        liquidatorFeeRate: 0.05e18,
  //        secBetweenSteps: 100
  //      })
  //    );
  //    createDefaultInsolventAuction(aliceAcc);
  //
  //    dutchAuction.continueInsolventAuction(aliceAcc);
  //
  //    vm.expectRevert(
  //      abi.encodeWithSelector(
  //        IDutchAuction.DA_CannotStepBeforeCoolDownEnds.selector,
  //        block.timestamp,
  //        block.timestamp + dutchAuction.insolventAuctionParams().secBetweenSteps
  //      )
  //    );
  //    dutchAuction.continueInsolventAuction(aliceAcc);
  //  }

  function _startDefaultInsolventAuction(uint acc) internal {
    // -500 init margin
    manager.setMockMargin(acc, true, -200e18);

    // -300 maintenance margin
    manager.setMockMargin(acc, false, -100e18);

    // mark to market: negative!!
    manager.setMarkToMarket(acc, -100e18);

    // start an auction on Alice's account
    dutchAuction.startAuction(acc, scenario);
  }
}
