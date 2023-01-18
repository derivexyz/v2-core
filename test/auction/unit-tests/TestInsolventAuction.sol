// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../../src/liquidation/DutchAuction.sol";
import "../../../src/Accounts.sol";
import "../../shared/mocks/MockERC20.sol";
import "../../shared/mocks/MockAsset.sol";
import "../../shared/mocks/MockSM.sol";

import "../../../src/liquidation/DutchAuction.sol";

import "../../shared/mocks/MockManager.sol";
import "../../shared/mocks/MockFeed.sol";
import "../DutchAuctionBase.sol";
import "forge-std/console2.sol";

contract UNIT_TestInvolventAuction is DutchAuctionBase {
  DutchAuction.DutchAuctionParameters public dutchAuctionParameters;

  uint tokenSubId = 1000;

  function setUp() public {
    deployMockSystem();
    setupAccounts();

    dutchAuction.setDutchAuctionParameters(
      DutchAuction.DutchAuctionParameters({
        stepInterval: 2,
        lengthOfAuction: 200,
        securityModule: address(1),
        portfolioModifier: 1e18,
        inversePortfolioModifier: 1e18
      })
    );

    usdc.mint(address(this), 1000_000_000e18);
    usdc.approve(address(usdcAsset), type(uint).max);
  }

  ///////////
  // TESTS //
  ///////////

  function testStartInsolventAuction() public {
    vm.startPrank(address(manager));

    int initMargin = -1000_000 * 1e18;

    // deposit marign to the account
    manager.setAccInitMargin(aliceAcc, initMargin); // 1 million bucks underwater

    // start an auction on Alice's account
    dutchAuction.startAuction(aliceAcc);
    DutchAuction.Auction memory auction = dutchAuction.getAuctionDetails(aliceAcc);
    assertEq(auction.insolvent, true); // start as insolvent from the very beginning
    assertEq(auction.auction.lowerBound, initMargin);

    // starts with 0 bid
    assertEq(dutchAuction.getCurrentBidPrice(aliceAcc), 0);

    // increment the insolvent auction
    // 1 of 200 steps
    dutchAuction.incrementInsolventAuction(aliceAcc);
    assertEq(dutchAuction.getCurrentBidPrice(aliceAcc), -5000e18);

    // 2 of 200 steps
    dutchAuction.incrementInsolventAuction(aliceAcc);
    assertEq(dutchAuction.getCurrentBidPrice(aliceAcc), -10_000e18);
  }

  function testBidForInsolventAuctionFromSM() public {
    int initMargin = -1000_000 * 1e18;
    manager.setAccInitMargin(aliceAcc, initMargin); // 1 million bucks underwater

    vm.prank(address(manager));
    dutchAuction.startAuction(aliceAcc);

    // 2 of 200 steps
    dutchAuction.incrementInsolventAuction(aliceAcc);
    dutchAuction.incrementInsolventAuction(aliceAcc);

    int expectedTotalPayoutFromSM = 10_000e18;

    // if sm has enough balance
    sm.mockBalance(expectedTotalPayoutFromSM);
    usdcAsset.deposit(sm.smAccountId(), uint(expectedTotalPayoutFromSM));

    assertEq(dutchAuction.getCurrentBidPrice(aliceAcc), -expectedTotalPayoutFromSM);

    int cashBefore = account.getBalance(bobAcc, usdcAsset, 0);

    vm.prank(bob);
    dutchAuction.bid(aliceAcc, bobAcc, 0.2e18); // bid for 20%

    int cashAfter = account.getBalance(bobAcc, usdcAsset, 0);

    assertEq(cashAfter - cashBefore, expectedTotalPayoutFromSM * 2 / 10);
    assertEq(usdcAsset.isSocialized(), false);
  }

  function testBidForInsolventAuctionMakesSMInsolvent() public {
    int initMargin = -1000_000 * 1e18;
    manager.setAccInitMargin(aliceAcc, initMargin); // 1 million bucks underwater

    vm.prank(address(manager));
    dutchAuction.startAuction(aliceAcc);

    // 2 of 200 steps
    dutchAuction.incrementInsolventAuction(aliceAcc);
    dutchAuction.incrementInsolventAuction(aliceAcc);

    int expectedTotalPayoutFromSM = 10_000e18;

    // if sm doesn't have enough balance
    sm.mockBalance(1000e18);
    usdcAsset.deposit(sm.smAccountId(), uint(1000e18));

    int cashBefore = account.getBalance(bobAcc, usdcAsset, 0);

    vm.prank(bob);
    dutchAuction.bid(aliceAcc, bobAcc, 1e18); // bid for 100%

    int cashAfter = account.getBalance(bobAcc, usdcAsset, 0);
    assertEq(cashAfter - cashBefore, expectedTotalPayoutFromSM);

    assertEq(usdcAsset.isSocialized(), true);
  }

  function testIncraseStepMax() public {
    int initMargin = -1000_000 * 1e18;
    manager.setAccInitMargin(aliceAcc, initMargin); // 1 million bucks underwater

    dutchAuction.setDutchAuctionParameters(
      DutchAuction.DutchAuctionParameters({
        stepInterval: 2,
        lengthOfAuction: 1,
        securityModule: address(1),
        portfolioModifier: 1e18,
        inversePortfolioModifier: 1e18
      })
    );
    vm.prank(address(manager));
    dutchAuction.startAuction(aliceAcc);

    dutchAuction.incrementInsolventAuction(aliceAcc);

    vm.expectRevert(IDutchAuction.DA_MaxStepReachedInsolventAuction.selector);
    dutchAuction.incrementInsolventAuction(aliceAcc);
  }
}
