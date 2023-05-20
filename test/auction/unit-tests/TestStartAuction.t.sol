//// SPDX-License-Identifier: UNLICENSED
//pragma solidity ^0.8.18;
//
//import "forge-std/Test.sol";
//
//import "../../../src/liquidation/DutchAuction.sol";
//import "../../../src/Accounts.sol";
//import "../../shared/mocks/MockERC20.sol";
//import "../../shared/mocks/MockAsset.sol";
//
//import "../../../src/liquidation/DutchAuction.sol";
//
//import "../../shared/mocks/MockManager.sol";
//import "../../shared/mocks/MockFeeds.sol";
//
//// Math library
//import "lyra-utils/decimals/DecimalMath.sol";
//
//contract UNIT_TestStartAuction is Test {
//  address alice;
//  address bob;
//  uint aliceAcc;
//  uint bobAcc;
//  Accounts account;
//  MockERC20 usdc;
//  MockAsset usdcAsset;
//  MockManager manager;
//  DutchAuction dutchAuction;
//  IDutchAuction.SolventAuctionParams public dutchAuctionParameters;
//
//  uint tokenSubId = 1000;
//
//  function setUp() public {
//    deployMockSystem();
//    setupAccounts();
//  }
//
//  function setupAccounts() public {
//    alice = address(0xaa);
//    bob = address(0xbb);
//    usdc.approve(address(usdcAsset), type(uint).max);
//    // usdcAsset.deposit(ownAcc, 0, 100_000_000e18);
//    aliceAcc = account.createAccount(alice, manager);
//    bobAcc = account.createAccount(bob, manager);
//  }
//
//  /// @dev deploy mock system
//  function deployMockSystem() public {
//    /* Base Layer */
//    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");
//
//    /* Wrappers */
//    usdc = new MockERC20("usdc", "USDC");
//
//    // usdc asset: deposit with usdc, cannot be negative
//    usdcAsset = new MockAsset(IERC20(usdc), account, false);
//    usdcAsset = new MockAsset(IERC20(usdc), account, false);
//
//    /* Risk Manager */
//    manager = new MockManager(address(account));
//
//    dutchAuction =
//      dutchAuction = new DutchAuction(manager, account, ISecurityModule(address(0)), ICashAsset(address(0)));
//
//    dutchAuctionParameters = IDutchAuction.SolventAuctionParams({
//      stepInterval: 1,
//      lengthOfAuction: 200,
//      secBetweenSteps: 0,
//      liquidatorFeeRate: 0.05e18
//    });
//
//    dutchAuction.setSolventAuctionParams(dutchAuctionParameters);
//  }
//
//  function mintAndDeposit(
//    address user,
//    uint accountId,
//    MockERC20 token,
//    MockAsset assetWrapper,
//    uint subId,
//    uint amount
//  ) public {
//    token.mint(user, amount);
//
//    vm.startPrank(user);
//    token.approve(address(assetWrapper), type(uint).max);
//    assetWrapper.deposit(accountId, subId, amount);
//    vm.stopPrank();
//  }
//
//  ///////////
//  // TESTS //
//  ///////////
//
//  function testCannotGetBidPriceOnNormalAccount() public {
//    vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_AuctionNotStarted.selector, aliceAcc));
//    dutchAuction.getCurrentBidPrice(aliceAcc);
//  }
//
//  /////////////////////////
//  // Start Auction Tests //
//  /////////////////////////
//
//  function testStartSolventAuctionRead() public {
//    _startDefaultSolventAuction(aliceAcc);
//
//    // testing that the view returns the correct auction.
//    DutchAuction.Auction memory auction = dutchAuction.getAuction(aliceAcc);
//
//    // log all the auction struct details
//    assertEq(auction.insolvent, false);
//    assertEq(auction.ongoing, true);
//    assertEq(auction.startTime, block.timestamp);
//
//    (int upperBound, int lowerBound) = dutchAuction.getBounds(aliceAcc);
//    assertEq(upperBound, 10000e18);
//    assertEq(lowerBound, -1000e18);
//
//    // getting the current bid price
//    int currentBidPrice = dutchAuction.getCurrentBidPrice(aliceAcc);
//    assertEq(currentBidPrice, 10_000e18);
//  }
//
//  function testStartInsolventAuctionRead() public {
//    _startDefaultInsolventAuction(aliceAcc);
//
//    // testing that the view returns the correct auction.
//    DutchAuction.Auction memory auction = dutchAuction.getAuction(aliceAcc);
//
//    // log all the auction struct details
//    assertEq(auction.insolvent, true);
//    assertEq(auction.ongoing, true);
//    assertEq(auction.startTime, block.timestamp);
//
//    (int upperBound, int lowerBound) = dutchAuction.getBounds(aliceAcc);
//    assertEq(upperBound, -1);
//    assertEq(lowerBound, -1000e18);
//
//    // getting the current bid price
//    int currentBidPrice = dutchAuction.getCurrentBidPrice(aliceAcc);
//    assertEq(currentBidPrice, 0);
//  }
//
//  function testCannotStartAuctionOnAccountAboveMargin() public {
//    vm.expectRevert(IDutchAuction.DA_AccountIsAboveMaintenanceMargin.selector);
//    dutchAuction.startAuction(aliceAcc);
//  }
//
//  function testStartAuctionAndCheckValues() public {
//    manager.giveAssets(aliceAcc);
//    manager.setMaintenanceMarginForPortfolio(-1);
//
//    // start an auction on Alice's account
//    dutchAuction.startAuction(aliceAcc);
//
//    // testing that the view returns the correct auction.
//    DutchAuction.Auction memory auction = dutchAuction.getAuction(aliceAcc);
//
//    (int upperBound, int lowerBound) = dutchAuction.getBounds(aliceAcc);
//    assertEq(auction.lowerBound, lowerBound);
//    assertEq(auction.upperBound, upperBound);
//  }
//
//  function testCannotStartAuctionAlreadyStarted() public {
//    _startDefaultSolventAuction(aliceAcc);
//
//    // start an auction on Alice's account
//    vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_AuctionAlreadyStarted.selector, aliceAcc));
//    dutchAuction.startAuction(aliceAcc);
//  }
//
//  // test that an auction can start as solvent and convert to insolvent
//  function testConvertToInsolventAuction() public {
//    _startDefaultSolventAuction(aliceAcc);
//
//    // testing that the view returns the correct auction.
//    DutchAuction.Auction memory auction = dutchAuction.getAuction(aliceAcc);
//    assertEq(auction.insolvent, false);
//
//    // fast forward
//    vm.warp(block.timestamp + dutchAuctionParameters.lengthOfAuction);
//    assertEq(dutchAuction.getCurrentBidPrice(aliceAcc), 0);
//
//    // mark the auction as insolvent
//    dutchAuction.convertToInsolventAuction(aliceAcc);
//
//    // testing that the view returns the correct auction.
//    auction = dutchAuction.getAuction(aliceAcc);
//    assertEq(auction.insolvent, true);
//
//    // cannot mark twice
//    vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_AuctionAlreadyInInsolvencyMode.selector, aliceAcc));
//    dutchAuction.convertToInsolventAuction(aliceAcc);
//  }
//
//  function testStartAuctionFailingOnGoingAuction() public {
//    _startDefaultSolventAuction(aliceAcc);
//
//    vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_AuctionAlreadyStarted.selector, aliceAcc));
//    dutchAuction.startAuction(aliceAcc);
//  }
//
//  function testCannotMarkInsolventIfAuctionNotInsolvent() public {
//    _startDefaultSolventAuction(aliceAcc);
//
//    // testing that the view returns the correct auction.
//    DutchAuction.Auction memory auction = dutchAuction.getAuction(aliceAcc);
//    assertEq(auction.accountId, aliceAcc);
//    assertEq(auction.ongoing, true);
//    assertEq(auction.insolvent, false);
//
//    assertGt(dutchAuction.getCurrentBidPrice(aliceAcc), 0);
//    // start an auction on Alice's account
//    vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_AuctionNotEnteredInsolvency.selector, aliceAcc));
//    dutchAuction.convertToInsolventAuction(aliceAcc);
//  }
//
//  function testGetMaxProportionNegativeMargin() public {
//    // mock MM and IM
//    manager.giveAssets(aliceAcc);
//    manager.setMaintenanceMarginForPortfolio(-1);
//    manager.setInitMarginForPortfolio(-100_000 * 1e18);
//
//    // start an auction on Alice's account
//    dutchAuction.startAuction(aliceAcc);
//
//    // getting the max proportion
//    uint maxProportion = dutchAuction.getMaxProportion(aliceAcc);
//    assertEq(maxProportion, 1e18); // 100% of the portfolio could be liquidated
//  }
//
//  function testGetMaxProportionPositiveMargin() public {
//    // mock MM and IM
//    manager.giveAssets(aliceAcc);
//    manager.setMaintenanceMarginForPortfolio(-1);
//    manager.setInitMarginForPortfolio(1000 * 1e18);
//
//    // start an auction on Alice's account
//    dutchAuction.startAuction(aliceAcc);
//
//    // getting the max proportion
//    uint maxProportion = dutchAuction.getMaxProportion(aliceAcc);
//    assertEq(maxProportion, 1e18); // 100% of the portfolio could be liquidated
//  }
//
//  function testGetMaxProportionWithAssets() public {
//    // mock MM and IM
//    _startDefaultSolventAuction(aliceAcc);
//
//    // getting the max proportion
//    uint maxProportion = dutchAuction.getMaxProportion(aliceAcc);
//    assertEq(percentageHelper(maxProportion), 909);
//    // TODO: check this value in the sim
//    // about 7% should be liquidate-able according to sim.
//  }
//
//  function testStartInsolventAuctionAndIncrement() public {
//    manager.giveAssets(aliceAcc);
//    manager.setMaintenanceMarginForPortfolio(-1);
//    manager.setInitMarginForPortfolio(-1000_000 * 1e18); // 1 million bucks underwater
//    manager.setInitMarginForInversedPortfolio(0); // price drops from 0
//
//    // start an auction on Alice's account
//    dutchAuction.startAuction(aliceAcc);
//
//    // testing that the view returns the correct auction.
//    DutchAuction.Auction memory auction = dutchAuction.getAuction(aliceAcc);
//    assertEq(auction.insolvent, true);
//
//    // getting the current bid price
//    int currentBidPrice = dutchAuction.getCurrentBidPrice(aliceAcc);
//    assertEq(currentBidPrice, 0); // starts at 0 as insolvent
//
//    // increment the insolvent auction
//    dutchAuction.continueInsolventAuction(aliceAcc);
//    // get the current step
//    uint currentStep = dutchAuction.getAuction(aliceAcc).stepInsolvent;
//    assertEq(currentStep, 1);
//  }
//
//  function testCannotStepNonInsolventAuction() public {
//    _startDefaultSolventAuction(aliceAcc);
//
//    // increment the insolvent auction
//    vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_SolventAuctionCannotIncrement.selector, aliceAcc));
//    dutchAuction.continueInsolventAuction(aliceAcc);
//  }
//
//  function testTerminatesSolventAuction() public {
//    _startDefaultSolventAuction(aliceAcc);
//
//    // testing that the view returns the correct auction.
//    DutchAuction.Auction memory auction = dutchAuction.getAuction(aliceAcc);
//    assertEq(auction.ongoing, true);
//
//    // deposit margin => makes IM(rv = 0) > 0
//    manager.setInitMarginForPortfolioZeroRV(15_000 * 1e18);
//    // terminate the auction
//    dutchAuction.terminateAuction(aliceAcc);
//    // check that the auction is terminated
//    assertEq(dutchAuction.getAuction(aliceAcc).ongoing, false);
//  }
//
//  function testTerminatesInsolventAuction() public {
//    _startDefaultInsolventAuction(aliceAcc);
//
//    // testing that the view returns the correct auction.
//    DutchAuction.Auction memory auction = dutchAuction.getAuction(aliceAcc);
//    assertEq(auction.ongoing, true);
//
//    // set maintenance margin > 0
//    manager.setMaintenanceMarginForPortfolio(5_000 * 1e18);
//    // terminate the auction
//    dutchAuction.terminateAuction(aliceAcc);
//    // check that the auction is terminated
//    assertEq(dutchAuction.getAuction(aliceAcc).ongoing, false);
//  }
//
//  function testCannotTerminateAuctionIfAccountIsUnderwater() public {
//    manager.giveAssets(aliceAcc);
//    manager.setMaintenanceMarginForPortfolio(-1);
//    manager.setInitMarginForPortfolio(-10000 * 1e18); // 1 million bucks
//
//    // start an auction on Alice's account
//    dutchAuction.startAuction(aliceAcc);
//
//    // terminate the auction
//    vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_AuctionCannotTerminate.selector, aliceAcc));
//    dutchAuction.terminateAuction(aliceAcc);
//  }
//
//  function _startDefaultSolventAuction(uint acc) internal {
//    manager.giveAssets(acc);
//
//    manager.setMaintenanceMarginForPortfolio(-1);
//    manager.setInitMarginForPortfolio(-1000 * 1e18); // -1000 underwater
//
//    // mock call if rv = 0
//    manager.setInitMarginForPortfolioZeroRV(-1000 * 1e18);
//
//    manager.setInitMarginForInversedPortfolio(10_000 * 1e18); // price drops from 10_000 => -1K
//
//    // start an auction on Alice's account
//    dutchAuction.startAuction(acc);
//  }
//
//  function _startDefaultInsolventAuction(uint acc) internal {
//    manager.giveAssets(acc);
//
//    manager.setMaintenanceMarginForPortfolio(-1);
//    manager.setInitMarginForPortfolio(-1000 * 1e18); // 1 thousand bucks
//
//    manager.setInitMarginForInversedPortfolio(-1); // price drops from -1 => -1000
//
//    // start an auction on Alice's account
//    dutchAuction.startAuction(acc);
//  }
//
//  /// Helper
//  // will round off the percentages at 2dp
//  function percentageHelper(uint bigNumberPercentage) public pure returns (uint) {
//    return bigNumberPercentage * 100 / 1e16;
//  }
//}
