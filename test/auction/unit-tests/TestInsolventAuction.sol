//// SPDX-License-Identifier: UNLICENSED
//pragma solidity ^0.8.18;
//
//import "forge-std/Test.sol";
//
//import "../../../src/liquidation/DutchAuction.sol";
//import "../../../src/Accounts.sol";
//import "../../shared/mocks/MockERC20.sol";
//import "../../shared/mocks/MockSM.sol";
//import "../mocks/MockCashAsset.sol";
//
//import "../../../src/liquidation/DutchAuction.sol";
//
//import "../../shared/mocks/MockManager.sol";
//import "../../shared/mocks/MockFeeds.sol";
//import "../DutchAuctionBase.sol";
//import "forge-std/console2.sol";
//
//contract UNIT_TestInvolventAuction is DutchAuctionBase {
//  DutchAuction.DutchAuctionParameters public dutchAuctionParameters;
//
//  uint tokenSubId = 1000;
//
//  function setUp() public {
//    deployMockSystem();
//    setupAccounts();
//
//    dutchAuction.setDutchAuctionParameters(
//      DutchAuction.DutchAuctionParameters({
//        stepInterval: 2,
//        lengthOfAuction: 200,
//        secBetweenSteps: 0,
//        liquidatorFeeRate: 0.05e18
//      })
//    );
//
//    usdc.mint(address(this), 1000_000_000e18);
//    usdc.approve(address(usdcAsset), type(uint).max);
//  }
//
//  function createDefaultInsolventAuction(uint accountId) public {
//    // slightly under maintenance margin
//    int maintenanceMargin = -1;
//
//    // init margin is also below 0
//    int initialMargin = -1000_000e18;
//
//    // inverted portfolio max value = 0
//    int inversedPortfolioIM = 0;
//
//    manager.giveAssets(accountId);
//
//    manager.setMaintenanceMarginForPortfolio(maintenanceMargin);
//    manager.setInitMarginForPortfolio(initialMargin); // lower bound
//    manager.setInitMarginForInversedPortfolio(inversedPortfolioIM);
//
//    dutchAuction.startAuction(accountId);
//  }
//
//  ///////////
//  // TESTS //
//  ///////////
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
//    dutchAuction.setDutchAuctionParameters(
//      DutchAuction.DutchAuctionParameters({
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
//    dutchAuction.setDutchAuctionParameters(
//      DutchAuction.DutchAuctionParameters({
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
//        block.timestamp + dutchAuction.getParameters().secBetweenSteps
//      )
//    );
//    dutchAuction.continueInsolventAuction(aliceAcc);
//  }
//}
