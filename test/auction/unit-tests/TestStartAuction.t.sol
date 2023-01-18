// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../../src/liquidation/DutchAuction.sol";
import "../../../src/Accounts.sol";
import "../../shared/mocks/MockERC20.sol";
import "../../shared/mocks/MockAsset.sol";

import "../../../src/liquidation/DutchAuction.sol";

import "../../shared/mocks/MockManager.sol";
import "../../shared/mocks/MockFeed.sol";
import "../../shared/mocks/MockIPCRM.sol";

// Math library
import "synthetix/DecimalMath.sol";

contract UNIT_TestStartAuction is Test {
  address alice;
  address bob;
  uint aliceAcc;
  uint bobAcc;
  Accounts account;
  MockERC20 usdc;
  MockAsset usdcAsset;
  MockIPCRM manager;
  DutchAuction dutchAuction;
  DutchAuction.DutchAuctionParameters public dutchAuctionParameters;

  uint tokenSubId = 1000;

  function setUp() public {
    deployMockSystem();
    setupAccounts();
  }

  function setupAccounts() public {
    alice = address(0xaa);
    bob = address(0xbb);
    usdc.approve(address(usdcAsset), type(uint).max);
    // usdcAsset.deposit(ownAcc, 0, 100_000_000e18);
    aliceAcc = account.createAccount(alice, manager);
    bobAcc = account.createAccount(bob, manager);
  }

  /// @dev deploy mock system
  function deployMockSystem() public {
    /* Base Layer */
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    /* Wrappers */
    usdc = new MockERC20("usdc", "USDC");

    // usdc asset: deposit with usdc, cannot be negative
    usdcAsset = new MockAsset(IERC20(usdc), account, false);
    usdcAsset = new MockAsset(IERC20(usdc), account, false);

    /* Risk Manager */
    manager = new MockIPCRM(address(account));

    dutchAuction = new DutchAuction(address(manager), address(account));

    dutchAuction.setDutchAuctionParameters(
      DutchAuction.DutchAuctionParameters({
        stepInterval: 1,
        lengthOfAuction: 200 * DecimalMath.UNIT,
        securityModule: address(1),
        portfolioModifier: 1e18,
        inversePortfolioModifier: 1e18
      })
    );

    dutchAuctionParameters = DutchAuction.DutchAuctionParameters({
      stepInterval: 1,
      lengthOfAuction: 200 * DecimalMath.UNIT,
      securityModule: address(1),
      portfolioModifier: 1e18,
      inversePortfolioModifier: 1e18
    });
  }

  function mintAndDeposit(
    address user,
    uint accountId,
    MockERC20 token,
    MockAsset assetWrapper,
    uint subId,
    uint amount
  ) public {
    token.mint(user, amount);

    vm.startPrank(user);
    token.approve(address(assetWrapper), type(uint).max);
    assetWrapper.deposit(accountId, subId, amount);
    vm.stopPrank();
  }

  ///////////
  // TESTS //
  ///////////

  /////////////////////////
  // Start Auction Tests //
  /////////////////////////

  function testStartAuctionRead() public {
    // making call from Riskmanager of the dutch auction contract
    vm.startPrank(address(manager));

    // start an auction on Alice's account
    dutchAuction.startAuction(aliceAcc);

    // testing that the view returns the correct auction.
    DutchAuction.Auction memory auction = dutchAuction.getAuctionDetails(aliceAcc);

    // log all the auction struct detials
    assertEq(auction.insolvent, true); // this would be flagged as an insolvent auction
    assertEq(auction.ongoing, true);
    assertEq(auction.startTime, block.timestamp);
    assertEq(auction.endTime, block.timestamp + dutchAuctionParameters.lengthOfAuction);

    uint spot = manager.getSpot();
    (int lowerBound, int upperBound) = dutchAuction.getBounds(aliceAcc, spot);
    assertEq(auction.auction.lowerBound, lowerBound);
    assertEq(auction.auction.upperBound, upperBound);

    // getting the current bid price
    int currentBidPrice = dutchAuction.getCurrentBidPrice(aliceAcc);
    assertEq(currentBidPrice, 0);
  }

  function testCannotStartWithNonManager() public {
    vm.startPrank(address(0xdead));

    // start an auction on Alice's account
    vm.expectRevert(IDutchAuction.DA_NotRiskManager.selector);
    dutchAuction.startAuction(aliceAcc);
  }

  function testStartAuctionAndCheckValues() public {
    vm.startPrank(address(manager));

    // start an auction on Alice's account
    dutchAuction.startAuction(aliceAcc);

    // testing that the view returns the correct auction.
    DutchAuction.Auction memory auction = dutchAuction.getAuctionDetails(aliceAcc);

    // TODO: calc v_min and v_max
    uint spot = manager.getSpot();
    (int lowerBound, int upperBound) = dutchAuction.getBounds(aliceAcc, spot);
    assertEq(auction.auction.lowerBound, lowerBound);
    assertEq(auction.auction.upperBound, upperBound);
  }

  function testCannotStartAuctionAlreadyStarted() public {
    vm.startPrank(address(manager));

    // start an auction on Alice's account
    dutchAuction.startAuction(aliceAcc);

    // start an auction on Alice's account
    vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_AuctionAlreadyStarted.selector, aliceAcc));
    dutchAuction.startAuction(aliceAcc);
  }

  // test that an auction is correcttly marked as insolvent
  function testInsolventAuction() public {
    vm.startPrank(address(manager));
    manager.setAccInitMargin(aliceAcc, 1000 * 1e18);
    manager.giveAssets(aliceAcc);
    manager.setMarginForPortfolio(10_000 * 1e18);
    // start an auction on Alice's account
    dutchAuction.startAuction(aliceAcc);

    // testing that the view returns the correct auction.
    DutchAuction.Auction memory auction = dutchAuction.getAuctionDetails(aliceAcc);
    assertEq(auction.insolvent, false);
    // fast forward
    vm.warp(block.timestamp + dutchAuctionParameters.lengthOfAuction + 1);
    assertEq(dutchAuction.getCurrentBidPrice(aliceAcc), 0);

    // mark the auction as insolvent
    dutchAuction.markAsInsolventLiquidation(aliceAcc);

    // testing that the view returns the correct auction.
    auction = dutchAuction.getAuctionDetails(aliceAcc);
    assertEq(auction.insolvent, true);
  }

  function testStartAuctionFailingOnGoingAuction() public {
    // wrong mark as insolvent not called by risk manager
    vm.startPrank(address(manager));

    // start an auction on Alice's account
    dutchAuction.startAuction(aliceAcc);
    vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_AuctionAlreadyStarted.selector, aliceAcc));
    dutchAuction.startAuction(aliceAcc);

    assertEq(dutchAuction.getAuctionDetails(aliceAcc).insolvent, true); // auction will start as insolvent
  }

  // test account with accoiunt id greater than 2
  function testStartAuctionWithAccountGreaterThan2() public {
    vm.startPrank(address(manager));

    // start an auction on Alice's account
    dutchAuction.startAuction(aliceAcc + 1);

    // testing that the view returns the correct auction.
    DutchAuction.Auction memory auction = dutchAuction.getAuctionDetails(aliceAcc + 1);
    assertEq(auction.auction.accountId, aliceAcc + 1);
    assertEq(auction.ongoing, true);
    assertEq(auction.startTime, block.timestamp);
    assertEq(auction.endTime, block.timestamp + dutchAuctionParameters.lengthOfAuction);
  }

  function testCannotMarkInsolventIfAuctionNotInsolvent() public {
    vm.startPrank(address(manager));

    // give assets
    manager.giveAssets(aliceAcc);
    manager.setMarginForPortfolio(10_000 * 1e18);
    // start an auction on Alice's account
    dutchAuction.startAuction(aliceAcc);

    // testing that the view returns the correct auction.
    DutchAuction.Auction memory auction = dutchAuction.getAuctionDetails(aliceAcc);
    assertEq(auction.auction.accountId, aliceAcc);
    assertEq(auction.ongoing, true);
    assertEq(auction.insolvent, false);

    assertGt(dutchAuction.getCurrentBidPrice(aliceAcc), 0);
    // start an auction on Alice's account
    vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_AuctionNotEnteredInsolvency.selector, aliceAcc));
    dutchAuction.markAsInsolventLiquidation(aliceAcc);
  }

  function testGetMaxProportionNegativeMargin() public {
    vm.startPrank(address(manager));
    // deposit marign to the account
    manager.setAccInitMargin(aliceAcc, -100_000 * 1e18);

    // start an auction on Alice's account
    dutchAuction.startAuction(aliceAcc);

    // getting the max proportion
    uint maxProportion = dutchAuction.getMaxProportion(aliceAcc);
    assertEq(maxProportion, 1e18); // 100% of the portfolio could be liquidated
  }

  function testGetMaxProportionPositiveMargin() public {
    vm.startPrank(address(manager));
    // deposit marign to the account
    manager.setAccInitMargin(aliceAcc, 1000 * 1e18);

    // start an auction on Alice's account
    dutchAuction.startAuction(aliceAcc);

    // getting the max proportion
    uint maxProportion = dutchAuction.getMaxProportion(aliceAcc);
    assertEq(maxProportion, 1e18); // 100% of the portfolio could be liquidated
  }

  function testGetMaxProportionWithAssets() public {
    vm.startPrank(address(manager));

    // deposit marign to the account
    manager.setAccInitMargin(aliceAcc, -1000 * 1e18); // set init margin for -1000

    // deposit assets to the account
    manager.giveAssets(aliceAcc);
    manager.setMarginForPortfolio(10_000 * 1e18);
    // start an auction on Alice's account
    dutchAuction.startAuction(aliceAcc);

    // getting the max proportion
    uint maxProportion = dutchAuction.getMaxProportion(aliceAcc);
    assertEq(percentageHelper(maxProportion), 909);
    // TODO: check this value in the sim
    // about 7% should be liquidateable according to sim.
  }

  // TODO: need to improve the manager for this test
  function testStartInsolventAuctionAndIncrement() public {
    vm.startPrank(address(manager));

    // deposit marign to the account
    manager.setAccInitMargin(aliceAcc, -1000 * 1e24); // 1 million bucks underwater

    // start an auction on Alice's account
    dutchAuction.startAuction(aliceAcc);

    // testing that the view returns the correct auction.
    DutchAuction.Auction memory auction = dutchAuction.getAuctionDetails(aliceAcc);
    assertEq(auction.insolvent, true);

    // getting the current bid price
    int currentBidPrice = dutchAuction.getCurrentBidPrice(aliceAcc);
    assertEq(currentBidPrice, 0); // starts at 0 as insolvent
    // mark as insolvent
    dutchAuction.markAsInsolventLiquidation(aliceAcc);

    // increment the insolvent auction
    dutchAuction.incrementInsolventAuction(aliceAcc);
    // get the current step
    uint currentStep = dutchAuction.getAuctionDetails(aliceAcc).stepInsolvent;
    assertEq(currentStep, 1);
  }

  function testCannotStepNonInsolventAuction() public {
    vm.startPrank(address(manager));

    // deposit marign to the account
    manager.setAccInitMargin(aliceAcc, 10000 * 1e18); // 1 million bucks

    // deposit assets to the account
    manager.giveAssets(aliceAcc);

    manager.setMarginForPortfolio(10_000 * 1e18);

    // start an auction on Alice's account
    dutchAuction.startAuction(aliceAcc);

    // increment the insolvent auction
    vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_SolventAuctionCannotIncrement.selector, aliceAcc));
    dutchAuction.incrementInsolventAuction(aliceAcc);
  }

  // manager successfully terminates an auction
  function testManagerTerminatesAuction() public {
    vm.startPrank(address(manager));

    // deposit marign to the account
    manager.setAccInitMargin(aliceAcc, -10000 * 1e18); // 1 thousand bucks
    manager.setMarginForPortfolio(10_000 * 1e18);
    // deposit assets to the account
    manager.giveAssets(aliceAcc);

    // start an auction on Alice's account
    dutchAuction.startAuction(aliceAcc);

    // testing that the view returns the correct auction.
    DutchAuction.Auction memory auction = dutchAuction.getAuctionDetails(aliceAcc);
    assertEq(auction.ongoing, true);

    // deposit margin
    manager.setAccInitMargin(aliceAcc, 15_000 * 1e18); // 1 thousand bucks
    // terminate the auction
    dutchAuction.terminateAuction(aliceAcc);
    // check that the auction is terminated
    assertEq(dutchAuction.getAuctionDetails(aliceAcc).ongoing, false);
  }

  // nonmanager cannot terminate an auction
  function testNonManagerCannotTerminateInsolventAuction() public {
    vm.startPrank(address(manager));

    // deposit marign to the account
    manager.setAccInitMargin(aliceAcc, -10000 * 1e18); // 1 million bucks

    // deposit assets to the account
    manager.giveAssets(aliceAcc);

    // start an auction on Alice's account
    dutchAuction.startAuction(aliceAcc);

    assertLt(manager.getInitialMargin(aliceAcc), 0);
    // terminate the auction
    vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_AuctionCannotTerminate.selector, aliceAcc));
    dutchAuction.terminateAuction(aliceAcc);
  }

  /// Helper
  // will round off the percentages at 2dp
  function percentageHelper(uint bigNumberPercantage) public pure returns (uint) {
    return bigNumberPercantage * 100 / 1e16;
  }
}
