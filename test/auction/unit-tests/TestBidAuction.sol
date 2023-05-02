// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

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
import "lyra-utils/decimals/DecimalMath.sol";
import "forge-std/console2.sol";

contract UNIT_BidAuction is Test {
  using SafeCast for int;
  using SafeCast for uint;
  using DecimalMath for uint;

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

  function setUp() public {
    deployMockSystem();
    setupAccounts();
  }

  function setupAccounts() public {
    alice = address(0xaa);
    bob = address(0xbb);
    usdc.approve(address(usdcAsset), type(uint).max);
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

    dutchAuction =
      dutchAuction = new DutchAuction(manager, account, ISecurityModule(address(0)), ICashAsset(address(0)));

    dutchAuctionParameters = DutchAuction.DutchAuctionParameters({
      stepInterval: 2,
      lengthOfAuction: 200,
      secBetweenSteps: 0,
      liquidatorFeeRate: 0.05e18
    });

    dutchAuction.setDutchAuctionParameters(dutchAuctionParameters);
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

  /////////////////////////
  // Start Auction Tests //
  /////////////////////////

  function testCannotBidOnAuctionThatHasNotStarted() public {
    // init margin is below 0, but not marked yet
    manager.giveAssets(aliceAcc);
    manager.setMaintenanceMarginForPortfolio(-1);
    manager.setInitMarginForPortfolioZeroRV(-1);

    vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_AuctionNotStarted.selector, aliceAcc));
    vm.prank(bob);
    dutchAuction.bid(aliceAcc, bobAcc, 50 * 1e16);
  }

  // todo: do we want to block bidding at 0?
  // it seems like letting people take with bid  = 0 is better than going insolvent
  function testCannotBidOnAuctionThatHasEnded() public {
    createDefaultSolventAuction(aliceAcc);

    vm.warp(block.timestamp + dutchAuctionParameters.lengthOfAuction + 5);
    // vm.expectRevert(IDutchAuction.DA_SolventAuctionEnded.selector);
    int bid = dutchAuction.getCurrentBidPrice(aliceAcc);
    assertEq(bid, 0);

    vm.expectRevert(IDutchAuction.DA_SolventAuctionEnded.selector);
    vm.prank(bob);
    dutchAuction.bid(aliceAcc, bobAcc, 50 * 1e16);
  }

  function testCannotBidForGreaterThanOneHundredPercent() public {
    createDefaultSolventAuction(aliceAcc);

    vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_AmountTooLarge.selector, aliceAcc, 101 * 1e16));
    dutchAuction.bid(aliceAcc, bobAcc, 101 * 1e16);
  }

  function testCannotMakeBidUnlessOwnerOfBidder() public {
    createDefaultSolventAuction(aliceAcc);

    vm.startPrank(bob);
    vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_BidderNotOwner.selector, aliceAcc, bob));
    dutchAuction.bid(aliceAcc, aliceAcc, 1e18);
  }

  function testBidOnSolventAuction() public {
    createDefaultSolventAuction(aliceAcc);

    // getting the max proportion
    uint maxProportion = dutchAuction.getMaxProportion(aliceAcc);
    assertLt(maxProportion, 5e17); // should be less than half

    // bidding
    vm.startPrank(bob);
    dutchAuction.bid(aliceAcc, bobAcc, 1e18);

    // the auction will keep going
    DutchAuction.Auction memory auction = dutchAuction.getAuction(aliceAcc);
    assertEq(auction.ongoing, true);
  }

  function testBidOnSolventAuctionCanAutomaticallyTerminate() public {
    createDefaultSolventAuction(aliceAcc);

    // mock that the next bid make the account above init margin
    manager.setNextIsEndingBid();

    // bidding
    vm.startPrank(bob);
    dutchAuction.bid(aliceAcc, bobAcc, 1e18);

    // the auction was terminated because init margin became 0 after the last bid
    DutchAuction.Auction memory auction = dutchAuction.getAuction(aliceAcc);
    assertEq(auction.ongoing, false);
  }

  function testCannotBidOnAuctionThatIsNoLongerLiquidatable() public {
    createDefaultSolventAuction(aliceAcc);

    // scenario: init margin with rv = 0 is back to positive
    manager.setInitMarginForPortfolioZeroRV(1);

    // bidding should not go through
    vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_AuctionShouldBeTerminated.selector, aliceAcc));
    vm.prank(bob);
    dutchAuction.bid(aliceAcc, bobAcc, 1e18);
  }

  function testCannotBid0() public {
    createDefaultSolventAuction(aliceAcc);

    vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_AmountIsZero.selector, aliceAcc));
    dutchAuction.bid(aliceAcc, bobAcc, 0);
  }

  // Bid a few times whilst the auction is solvent and check if it correctly recalculates bounds
  // and terminates.
  function testBidTillSolventThenClose() public {
    createDefaultSolventAuction(aliceAcc);

    DutchAuction.Auction memory auction = dutchAuction.getAuction(aliceAcc);

    uint p_max = dutchAuction.getMaxProportion(aliceAcc);

    // bid for half and make sure the auction doesn't terminate
    vm.startPrank(bob);
    dutchAuction.bid(aliceAcc, bobAcc, p_max.divideDecimal(2 * 1e18));

    // checks bounds have not changed
    auction = dutchAuction.getAuction(aliceAcc);
    assertEq(auction.ongoing, true);
    assertEq(auction.insolvent, false);

    vm.warp(block.timestamp + (dutchAuctionParameters.lengthOfAuction) / 2);
    p_max = dutchAuction.getMaxProportion(aliceAcc);
    dutchAuction.bid(aliceAcc, bobAcc, p_max.divideDecimal(2 * 1e18));

    // checks bounds have not changed
    auction = dutchAuction.getAuction(aliceAcc);
    assertEq(auction.ongoing, true);
    assertEq(auction.insolvent, false);

    // bid for the remaining amount of the account should close end the auction
    manager.setNextIsEndingBid(); // mock the account to return

    dutchAuction.bid(aliceAcc, bobAcc, 1e18);

    auction = dutchAuction.getAuction(aliceAcc);
    assertEq(auction.ongoing, false);
  }

  function testBidFeeCalculation() public {
    int initMargin = -10_000e18;

    // create solvent auction: -10K underwater, invert portfolio is 10K
    createAuctionOnUser(aliceAcc, -1, initMargin, -initMargin);

    vm.warp(block.timestamp + (dutchAuctionParameters.lengthOfAuction) / 2);

    // getting the max proportion
    int bidPrice = dutchAuction.getCurrentBidPrice(aliceAcc);
    uint maxBid = dutchAuction.getMaxProportion(aliceAcc);

    // bid with max percentage
    vm.prank(bob);
    (uint percentage, uint costPaid,, uint fee) = dutchAuction.bid(aliceAcc, bobAcc, 1e18);
    assertEq(costPaid, uint(bidPrice) * maxBid / 1e18);
    assertEq(fee, costPaid * 5 / 100);

    // todo[Anton]: check numbers
    assertEq(percentage, 571428571428571428); // 57% of portfolio get liquidated
  }

  // handle branch coverage where during IM check, the call to manager could rever
  function testBidOnSolventAuctionRevert() public {
    createDefaultSolventAuction(aliceAcc);

    // getting the max proportion
    uint maxProportion = dutchAuction.getMaxProportion(aliceAcc);
    assertLt(maxProportion, 5e17); // should be less than half

    // bidding
    vm.startPrank(bob);
    manager.setRevertMargin();
    vm.expectRevert();
    dutchAuction.bid(aliceAcc, bobAcc, 1e18);
  }

  /////////////
  // helpers //
  /////////////

  function createDefaultSolventAuction(uint accountId) public {
    int maintenanceMargin = -1e18;
    int initMargin = -1000e18;
    int inversedPortfolioIM = 1500e18; // price drops from 1500 => 0
    createAuctionOnUser(accountId, maintenanceMargin, initMargin, inversedPortfolioIM);
  }

  function createAuctionOnUser(uint accountId, int maintenanceMargin, int initMargin, int inversedPortfolioIM) public {
    manager.giveAssets(accountId);

    manager.setMaintenanceMarginForPortfolio(maintenanceMargin);
    manager.setInitMarginForPortfolio(initMargin);
    manager.setInitMarginForInversedPortfolio(inversedPortfolioIM);

    // currently set this to the same as init margin
    manager.setInitMarginForPortfolioZeroRV(initMargin);

    dutchAuction.startAuction(accountId);
  }
}
