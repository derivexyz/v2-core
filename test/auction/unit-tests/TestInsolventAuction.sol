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
  }

  ///////////
  // TESTS //
  ///////////


  function testStartInsolventAuction() public {
    vm.startPrank(address(manager));

    // deposit marign to the account
    manager.depositMargin(aliceAcc, -1000 * 1e24); // 1 million bucks underwater

    // start an auction on Alice's account
    dutchAuction.startAuction(aliceAcc);
    DutchAuction.Auction memory auction = dutchAuction.getAuctionDetails(aliceAcc);
    assertEq(auction.insolvent, true); // start as insolvent from the very beginning

    console2.log(auction.dv);

    // increment the insolvent auction
    dutchAuction.incrementInsolventAuction(aliceAcc);
    dutchAuction.incrementInsolventAuction(aliceAcc);
    
    int currentBidPrice = dutchAuction.getCurrentBidPrice(aliceAcc);
    assertGt(0, currentBidPrice);
    
  }
}
