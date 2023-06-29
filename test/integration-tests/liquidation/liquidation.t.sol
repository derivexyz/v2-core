// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "lyra-utils/encoding/OptionEncoding.sol";

import "../shared/IntegrationTestBase.t.sol";
import {IManager} from "src/interfaces/IManager.sol";

/**
 * @dev testing liquidation process
 */
contract INTEGRATION_Liquidation is IntegrationTestBase {
  // value used for test
  int constant amountOfContracts = 1e18;
  uint constant strike = 2000e18;

  uint96 callId;
  uint96 putId;
  uint64 expiry;

  IOption option;

  function setUp() public {
    _setupIntegrationTestComplete();

    _depositCash(alice, aliceAcc, 1200e18);
    _depositCash(bob, bobAcc, 1200e18);

    expiry = uint64(block.timestamp + 7 days);

    _setForwardPrice("weth", expiry, 2000e18, 1e18);
    _setDefaultSVIForExpiry("weth", expiry);
    _setInterestRate("weth", expiry, 0.01e18, 1e18);

    callId = OptionEncoding.toSubId(expiry, strike, true);
    putId = OptionEncoding.toSubId(expiry, strike, false);

    option = markets["weth"].option;
  }

  // test auction starting price and bidding price
  function testAuctionFlow() public {
    _tradeCall(aliceAcc, bobAcc);

    vm.warp(block.timestamp + 3 hours);
    _setSpotPrice("weth", 3000e18, 1e18);
    _setForwardPrice("weth", expiry, 3000e18, 1e18);
    _setDefaultSVIForExpiry("weth", expiry);

    // MM is negative
    assertLt(getAccMaintenanceMargin(aliceAcc) / 1e18, 0);

    // can start this auction
    auction.startAuction(aliceAcc, 1);

    _setSpotPrice("weth", 2040e18, 1e18);

    assertGt(getAccMaintenanceMargin(aliceAcc), 0);

    auction.terminateAuction(aliceAcc);
    DutchAuction.Auction memory auctionInfo = auction.getAuction(aliceAcc);
    assertEq(auctionInfo.ongoing, false);
  }

  function testLiquidateAccountUnderDifferentManager() public {
    // charlieAcc is controlled by PMRM
    address charlie = address(0xccc);
    PMRM manager = markets["weth"].pmrm;
    uint charlieAcc = subAccounts.createAccountWithApproval(charlie, address(this), manager);
    _depositCash(charlie, charlieAcc, 1900e18);

    _tradeCall(charlieAcc, bobAcc);

    _setSpotPrice("weth", 3200e18, 1e18);
    _setForwardPrice("weth", expiry, 3200e18, 1e18);
    _setDefaultSVIForExpiry("weth", expiry);

    // MM is negative
    assertLt(getAccMaintenanceMargin(charlieAcc) / 1e18, 0);

    // can start this auction
    auction.startAuction(charlieAcc, 1);

    _setSpotPrice("weth", 2040e18, 1e18);

    assertGt(getAccMaintenanceMargin(charlieAcc), 0);

    auction.terminateAuction(charlieAcc);
    DutchAuction.Auction memory auctionInfo = auction.getAuction(aliceAcc);
    assertEq(auctionInfo.ongoing, false);
  }

  //  function testFuzzAuctionCannotRestartAfterTermination(uint newSpot_) public {
  //    int newSpot = int(newSpot_); // wrap into int here, specifying int as input will have too many invalid inputs
  //    vm.assume(newSpot > 1000e18);
  //    vm.assume(newSpot < 2100e18); // price where it got mark as liquidatable

  //    // as long as an auction is terminate-able when price is back to {newSpot}
  //    // it cannot be restart immediate after termination

  //    // alice is short 10 calls
  //    _tradeCall();

  //    // update price to make IM < 0
  //    vm.warp(block.timestamp + 12 hours);
  //    _setSpotPriceE18(2500e18);
  //    _updateJumps();

  //    // account is liquidatable at this point
  //    auction.startAuction(aliceAcc);

  //    // can terminate auction if IM (RV = 0) > 0
  //    _setSpotPriceE18(newSpot);

  //    // if account IM(rv) > 0, it can be terminated
  //    if (getAccInitMarginRVZero(aliceAcc) > 0) {
  //      // if it's terminate-able, terminate and cannot restart
  //      auction.terminateAuction(aliceAcc);

  //      vm.expectRevert(IDutchAuction.DA_AccountIsAboveMaintenanceMargin.selector);
  //      auction.startAuction(aliceAcc);
  //    } else {
  //      // cannot terminate
  //      vm.expectRevert(abi.encodeWithSelector(IDutchAuction.DA_AuctionCannotTerminate.selector, aliceAcc));
  //      auction.terminateAuction(aliceAcc);
  //    }
  //  }

  ///@dev alice go short, bob go long
  function _tradeCall(uint fromAcc, uint toAcc) public {
    int premium = 225e18;
    // alice send call to bob, bob send premium to alice
    _submitTrade(fromAcc, option, callId, amountOfContracts, toAcc, cash, 0, premium);
  }
}
