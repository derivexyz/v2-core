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

// Math library...

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

  uint UNIT = 1e18;

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

    dutchAuction = new DutchAuction(address(manager));

    dutchAuction.setDutchAuctionParameters(
      DutchAuction.DutchAuctionParameters({
        stepInterval: 2 * UNIT,
        lengthOfAuction: 200 * UNIT,
        securityModule: address(1)
      })
    );

    dutchAuctionParameters = DutchAuction.DutchAuctionParameters({
      stepInterval: 2 * UNIT,
      lengthOfAuction: 200 * UNIT,
      securityModule: address(1)
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
    assertEq(auction.insolvent, false);
    assertEq(auction.ongoing, true);
    assertEq(auction.startTime, block.timestamp);
    assertEq(auction.endTime, block.timestamp + dutchAuctionParameters.lengthOfAuction);

    uint spot = manager.getSpot();
    (int lowerBound, int upperBound) = dutchAuction.getBounds(aliceAcc, spot);
    assertEq(auction.auction.lowerBound, lowerBound);
    assertEq(auction.auction.upperBound, upperBound);

    assertEq(auction.auction.accountId, aliceAcc);

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
    assertEq(auction.auction.accountId, aliceAcc);
    assertEq(auction.ongoing, true);
    assertEq(auction.startTime, block.timestamp);
    assertEq(auction.endTime, block.timestamp + dutchAuctionParameters.lengthOfAuction);

    // TODO: calc v_min and v_max
    uint spot = manager.getSpot();
    (int lowerBound, int upperBound) = dutchAuction.getBounds(aliceAcc, spot);
    assertEq(auction.auction.lowerBound, lowerBound);
    assertEq(auction.auction.upperBound, upperBound);
  }

  function testFailAuctionAlreadyStarted() public {
    vm.startPrank(address(manager));

    // start an auction on Alice's account
    dutchAuction.startAuction(aliceAcc);

    // start an auction on Alice's account
    vm.expectRevert(IDutchAuction.DA_AuctionAlreadyStarted.selector);
    dutchAuction.startAuction(aliceAcc);
  }

  // test that an auction is correcttly marked as insolvent
  function testInsolventAuction() public {
    vm.startPrank(address(manager));

    // start an auction on Alice's account
    dutchAuction.startAuction(aliceAcc);

    // testing that the view returns the correct auction.
    DutchAuction.Auction memory auction = dutchAuction.getAuctionDetails(aliceAcc);
    assertEq(auction.insolvent, false);

    // fast forward
    vm.warp(block.timestamp + dutchAuctionParameters.lengthOfAuction / 2);
    // mark the auction as insolvent
    dutchAuction.markAsInsolventLiquidation(aliceAcc);

    // testing that the view returns the correct auction.
    auction = dutchAuction.getAuctionDetails(aliceAcc);
    assertEq(auction.insolvent, true);
  }

  function testFailingInsolventAuctionNotRiskManager() public {
    // wrong mark as insolvent not called by risk manager
    vm.startPrank(address(manager));

    // start an auction on Alice's account
    dutchAuction.startAuction(aliceAcc);
    vm.stopPrank();
    // fastforward change address to 0xdead and then catch revert after calling mark insolvent
    vm.warp(block.timestamp + dutchAuctionParameters.lengthOfAuction / 2);
    vm.startPrank(address(0xdead));
    vm.expectRevert("DA_NotRiskManager");
    dutchAuction.markAsInsolventLiquidation(aliceAcc);
  }

  function testStartAuctionFailingOnGoingAuction() public {
    // wrong mark as insolvent not called by risk manager
    vm.startPrank(address(manager));

    // start an auction on Alice's account
    dutchAuction.startAuction(aliceAcc);
    int currentBidPrice = dutchAuction.getCurrentBidPrice(aliceAcc);
    assertEq(currentBidPrice, 0);
    vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_AuctionAlreadyStarted.selector, aliceAcc));
    dutchAuction.startAuction(aliceAcc);

    assertEq(dutchAuction.getAuctionDetails(aliceAcc).insolvent, false);
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

  function testFailingInsolventAuctionNotInsolvent() public {

    vm.startPrank(address(manager));

    // give assets
    manager.giveAssets(aliceAcc);

    // start an auction on Alice's account
    dutchAuction.startAuction(aliceAcc);

    // testing that the view returns the correct auction.
    DutchAuction.Auction memory auction = dutchAuction.getAuctionDetails(aliceAcc);
    assertEq(auction.auction.accountId, aliceAcc);
    assertEq(auction.ongoing, true);
    assertEq(auction.startTime, block.timestamp);
    assertEq(auction.endTime, block.timestamp + dutchAuctionParameters.lengthOfAuction);
    
    assertGt(dutchAuction.getCurrentBidPrice(aliceAcc), 0);
    // start an auction on Alice's account
    vm.expectRevert("DA_AuctionNotEnteredInsolvency");
    dutchAuction.markAsInsolventLiquidation(aliceAcc);
  }

  function testGetMaxProportion() public {
    vm.startPrank(address(manager));

    // start an auction on Alice's account
    dutchAuction.startAuction(aliceAcc);

    // testing that the view returns the correct auction.
    DutchAuction.Auction memory auction = dutchAuction.getAuctionDetails(aliceAcc);
    assertEq(auction.auction.accountId, aliceAcc);
    assertEq(auction.ongoing, true);
    assertEq(auction.startTime, block.timestamp);
    assertEq(auction.endTime, block.timestamp + dutchAuctionParameters.lengthOfAuction);

    // getting the current bid price
    int currentBidPrice = dutchAuction.getCurrentBidPrice(aliceAcc);
    assertEq(currentBidPrice, 0);

    // deposit marign to the account
    manager.depositMargin(aliceAcc, 1000 * 1e18);

    // getting the max proportion
    uint maxProportion = dutchAuction.getMaxProportion(aliceAcc);
    assertEq(maxProportion, 1e18); // 100% of the portfolio could be liquidated
  }

  function testGetMaxProportionWithAssets() public {
    vm.startPrank(address(manager));

    // deposit marign to the account
    manager.depositMargin(aliceAcc, 1000 * 1e18);

    // deposit assets to the account
    manager.giveAssets(aliceAcc);

    // start an auction on Alice's account
    dutchAuction.startAuction(aliceAcc);

    // testing that the view returns the correct auction.
    DutchAuction.Auction memory auction = dutchAuction.getAuctionDetails(aliceAcc);
    assertEq(auction.auction.accountId, aliceAcc);
    assertEq(auction.ongoing, true);
    assertEq(auction.startTime, block.timestamp);
    assertEq(auction.endTime, block.timestamp + dutchAuctionParameters.lengthOfAuction);

    // getting the current bid price
    int currentBidPrice = dutchAuction.getCurrentBidPrice(aliceAcc);
    assertGt(currentBidPrice, 0);

    // getting the max proportion
    uint maxProportion = dutchAuction.getMaxProportion(aliceAcc);
    assertEq(maxProportion, 1e18); // 100% of the portfolio could be liquidated
  }
}
