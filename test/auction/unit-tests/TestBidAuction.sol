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

    dutchAuction.setDutchAuctionParameters(
      DutchAuction.DutchAuctionParameters({
        stepInterval: 2,
        lengthOfAuction: 200,
        securityModule: address(1),
        portfolioModifier: 1e18,
        inversePortfolioModifier: 1e18
      })
    );

    dutchAuctionParameters = DutchAuction.DutchAuctionParameters({
      stepInterval: 2,
      lengthOfAuction: 200,
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

  function testCannotBidOnAuctionThatHasNotStarted() public {
    vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_AuctionEnded.selector, aliceAcc));
    vm.prank(bob);
    dutchAuction.bid(aliceAcc, bobAcc, 50 * 1e16);
  }

  function testCannotBidOnAuctionThatHasEnded() public {
    vm.prank(address(manager));
    dutchAuction.startAuction(aliceAcc);
    uint endTime = dutchAuction.getAuctionDetails(aliceAcc).endTime;
    vm.warp(endTime + 10);
    vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_AuctionEnded.selector, aliceAcc));
    dutchAuction.bid(aliceAcc, bobAcc, 50 * 1e16);
  }

  function testCannotBidForGreaterThanOneHundredPercent() public {
    vm.prank(address(manager));
    dutchAuction.startAuction(aliceAcc);
    vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_AmountTooLarge.selector, aliceAcc, 101 * 1e16));
    dutchAuction.bid(aliceAcc, bobAcc, 101 * 1e16);
  }

  function testCannotMakeBidUnlessOwnerOfBidder() public {
    vm.startPrank(address(manager));

    // start an auction on Alice's account
    dutchAuction.startAuction(aliceAcc);

    // bidding
    vm.stopPrank();
    vm.startPrank(bob);
    vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_BidderNotOwner.selector, aliceAcc, bob));
    dutchAuction.bid(aliceAcc, aliceAcc, 1e18);
  }

  function testBidOnSolventAuction() public {
    vm.startPrank(address(manager));

    manager.giveAssets(aliceAcc);

    // set the initialMargin result for the portfolio
    manager.setMarginForPortfolio(10_000 * 1e18);

    dutchAuction.startAuction(aliceAcc);

    // getting the max proportion
    uint maxProportion = dutchAuction.getMaxProportion(aliceAcc);
    assertLt(maxProportion, 5e17); // should be less than half

    // bidding
    vm.stopPrank();

    vm.startPrank(bob);
    dutchAuction.bid(aliceAcc, bobAcc, 1e18);

    // testing that the auction is ended because init margin is 0
    manager.setAccInitMargin(aliceAcc, 0);
    DutchAuction.Auction memory auction = dutchAuction.getAuctionDetails(aliceAcc);
    assertEq(auction.ongoing, false);
  }

  function testCannotBid0() public {
    vm.prank(address(manager));
    dutchAuction.startAuction(aliceAcc);
    vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_AmountInvalid.selector, aliceAcc, 0));
    dutchAuction.bid(aliceAcc, bobAcc, 0);
  }

  // Bid a few times whilst the auction is solvent and check if it correctly recalcs bounds
  // and terminates.
  function testBidTillSolventThenClose() public {
    createAuctionOnUser(aliceAcc, -10_000 * 1e18, 20_000 * 1e18);

    DutchAuction.Auction memory auction = dutchAuction.getAuctionDetails(aliceAcc);

    uint p_max = dutchAuction.getMaxProportion(aliceAcc);

    // bid for half and make sure the auction doesn't terminate
    vm.startPrank(bob);
    dutchAuction.bid(aliceAcc, bobAcc, p_max.divideDecimal(2 * 1e18));

    // checks bounds have not changed
    auction = dutchAuction.getAuctionDetails(aliceAcc);
    assertEq(auction.ongoing, true);
    assertEq(auction.insolvent, false);

    vm.warp(block.timestamp + (auction.endTime - block.timestamp) / 2);
    assertLt(block.timestamp, auction.endTime);
    p_max = dutchAuction.getMaxProportion(aliceAcc);
    dutchAuction.bid(aliceAcc, bobAcc, p_max.divideDecimal(2 * 1e18));

    // checks bounds have not changed
    auction = dutchAuction.getAuctionDetails(aliceAcc);
    assertEq(auction.ongoing, true);
    assertEq(auction.insolvent, false);

    // // bid for the remaing amount of the account should close end the auction
    manager.setNextIsEndingBid(); // mock the account to return

    dutchAuction.bid(aliceAcc, bobAcc, 1e18);

    auction = dutchAuction.getAuctionDetails(aliceAcc);
    assertEq(auction.ongoing, false);
  }

  /////////////
  // helpers //
  /////////////

  function createAuctionOnUser(uint accountId, int margin, int invMargin) public {
    vm.startPrank(address(manager));
    manager.giveAssets(accountId);
    manager.setAccInitMargin(accountId, margin);
    manager.setMarginForPortfolio(invMargin);
    dutchAuction.startAuction(accountId);
    vm.stopPrank();
  }
}
