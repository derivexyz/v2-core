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
      DutchAuction.DutchAuctionParameters({
        stepInterval: 2 * DecimalMath.UNIT,
        lengthOfAuction: 200 * DecimalMath.UNIT,
        securityModule: address(1)
      })
    );

    dutchAuctionParameters = DutchAuction.DutchAuctionParameters({
      stepInterval: 2 * DecimalMath.UNIT,
      lengthOfAuction: 200 * DecimalMath.UNIT,
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

  function testCannotBidOnAuctionThatHasNotStarted() public {
    vm.prank(address(manager));
    vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_AuctionNotOngoing.selector, aliceAcc));
    dutchAuction.bid(aliceAcc, 50 * 1e16);
  }

  function testCannotBidOnAuctionThatHasEnded() public {
    vm.prank(address(manager));
    dutchAuction.startAuction(aliceAcc);
    uint endTime = dutchAuction.getAuctionDetails(aliceAcc).endTime;
    vm.warp(endTime + 10);
    console.log('block time stamp', block.timestamp);
    console.log('end time', endTime);
    vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_AuctionEnded.selector, aliceAcc));
    dutchAuction.bid(aliceAcc, 50 * 1e16);
  }

  function testCannotBidForGreaterThanOneHundredPercent() public {
    vm.prank(address(manager));
    dutchAuction.startAuction(aliceAcc);
    vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_AmountTooLarge.selector, aliceAcc, 101 * 1e16));
    dutchAuction.bid(aliceAcc, 101 * 1e16);
  }

  function testCannotBid0() public {
    vm.prank(address(manager));
    dutchAuction.startAuction(aliceAcc);
    vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_AmountInvalid.selector, aliceAcc, 0));
    dutchAuction.bid(aliceAcc, 0);
  }
}