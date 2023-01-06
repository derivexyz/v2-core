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

    dutchAuction = new DutchAuction(address(manager));

    dutchAuction.setDutchAuctionParameters(
      DutchAuction.DutchAuctionParameters({stepInterval: 2, lengthOfAuction: 200, securityModule: address(1)})
    );

    dutchAuctionParameters = DutchAuction.DutchAuctionParameters({stepInterval: 2, lengthOfAuction: 200, securityModule: address(1)});
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
    (int lowerBound, int upperBound) = dutchAuction.getBounds(aliceAcc, 1000);
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
    (int lowerBound, int upperBound) = dutchAuction.getBounds(aliceAcc, 1000);
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


}
