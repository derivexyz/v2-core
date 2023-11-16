// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "lyra-utils/encoding/OptionEncoding.sol";

import "../shared/IntegrationTestBase.t.sol";

import {getDefaultAuctionParam} from "../../../scripts/config-local.sol";
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

  IOptionAsset option;

  address charlie = address(0xccc);

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

  ///@dev alice go short, bob go long
  function _tradeCall(uint fromAcc, uint toAcc) internal {
    int premium = 225e18;
    // alice send call to bob, bob send premium to alice
    _submitTrade(fromAcc, option, callId, amountOfContracts, toAcc, cash, 0, premium);
  }

  function _tradePerp(uint fromAcc, uint toAcc) internal {
    _submitTrade(fromAcc, markets["weth"].perp, 0, amountOfContracts, toAcc, cash, 0, 0);
  }

  function _refreshOracles(uint96 price) internal {
    _setSpotPrice("weth", price, 1e18);
    _setForwardPrice("weth", expiry, price, 1e18);
    _setDefaultSVIForExpiry("weth", expiry);
  }

  // test auction starting price and bidding price
  function testAuctionFlow() public {
    _tradeCall(aliceAcc, bobAcc);

    vm.warp(block.timestamp + 3 hours);
    _refreshOracles(3000e18);

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
    PMRM manager = markets["weth"].pmrm;
    uint charlieAcc = subAccounts.createAccountWithApproval(charlie, address(this), manager);
    _depositCash(charlie, charlieAcc, 1900e18);

    _tradeCall(charlieAcc, bobAcc);
    _refreshOracles(3200e18);

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

  function testLiquidationRaceCondition() public {
    uint scenario = 0;
    _tradeCall(aliceAcc, bobAcc);

    _refreshOracles(2600e18);

    // start an auction on alice's account
    auction.startAuction(aliceAcc, scenario);

    uint liquidator1 = subAccounts.createAccountWithApproval(charlie, address(this), srm);
    uint liquidator2 = subAccounts.createAccountWithApproval(charlie, address(this), srm);

    _depositCash(charlie, liquidator1, 5000e18);
    _depositCash(charlie, liquidator2, 5000e18);

    vm.warp(block.timestamp + 10 minutes);
    _refreshOracles(2600e18);

    // max it can bid is around 60%
    uint maxPercentageToBid = auction.getMaxProportion(aliceAcc, scenario);
    assertEq(maxPercentageToBid / 1e16, 60);

    // liquidator 1 bid 30%
    vm.startPrank(charlie);
    uint percentageToBid = maxPercentageToBid / 2;
    (uint finalPercentage1, uint cashFromLiquidator1,) = auction.bid(aliceAcc, liquidator1, percentageToBid, 0, 0);
    assertEq(finalPercentage1, percentageToBid);

    uint bidPercent2 = percentageToBid * 1e18 / (1e18 - percentageToBid);
    // liquidator 2 also bid 30% of original, but it is executed after liquidator 1
    (uint finalPercentage2, uint cashFromLiquidator2,) = auction.bid(aliceAcc, liquidator2, bidPercent2, 0, 0);
    assertEq(finalPercentage2, bidPercent2);
    assertApproxEqAbs(cashFromLiquidator1, cashFromLiquidator2, 10); // very very close

    vm.stopPrank();
  }

  function testLiquidationFrontrunProtection() public {
    uint scenario = 0;
    _tradeCall(aliceAcc, bobAcc);
    _refreshOracles(2600e18);

    auction.startAuction(aliceAcc, scenario);

    uint liquidator1 = subAccounts.createAccountWithApproval(charlie, address(this), srm);
    uint liquidator2 = subAccounts.createAccountWithApproval(charlie, address(this), srm);

    _depositCash(charlie, liquidator1, 5000e18);
    _depositCash(charlie, liquidator2, 5000e18);

    vm.warp(block.timestamp + 10 minutes);
    _refreshOracles(2600e18);

    // max it can bid is around 60%
    uint maxPercentageToBid = auction.getMaxProportion(aliceAcc, scenario);
    uint lastTradeId = subAccounts.lastAccountTradeId(aliceAcc);

    vm.startPrank(charlie);
    uint percentageToBid = maxPercentageToBid / 2;
    auction.bid(aliceAcc, liquidator1, percentageToBid, 0, lastTradeId);

    // Liquidator 2 reverts, because the portfolio changed since lastTradeId
    vm.expectRevert(IDutchAuction.DA_InvalidLastTradeId.selector);
    auction.bid(aliceAcc, liquidator2, percentageToBid, 0, lastTradeId);

    vm.stopPrank();
  }

  function testCannotMakeBidderPayMoreThanCashLimit() public {
    // Front running issue:
    // depositing (updating account with positive value) last second may result in making liquidator pay more than intended

    uint scenario = 0;
    _tradeCall(aliceAcc, bobAcc);

    _refreshOracles(2600e18);

    // start an auction on alice's account
    auction.startAuction(aliceAcc, scenario);

    uint liquidator1 = subAccounts.createAccountWithApproval(charlie, address(this), srm);
    uint liquidator2 = subAccounts.createAccountWithApproval(charlie, address(this), srm);

    _depositCash(charlie, liquidator1, 5000e18);
    _depositCash(charlie, liquidator2, 5000e18);

    vm.warp(block.timestamp + 10 minutes);
    _refreshOracles(2600e18);

    // max it can bid is around 60%
    uint maxPercentageToBid = auction.getMaxProportion(aliceAcc, scenario);
    assertEq(maxPercentageToBid / 1e16, 60);

    // liquidator 1 bid 10%
    vm.startPrank(charlie);
    uint percentageToBid = 0.1e18;
    (uint finalPercentage1, uint cashFromLiquidator1,) = auction.bid(aliceAcc, liquidator1, percentageToBid, 0, 0);
    assertEq(finalPercentage1, percentageToBid);
    vm.stopPrank();

    // make limit slightly lower so the bid will revert

    // bid reverts
    vm.startPrank(charlie);
    vm.expectRevert(IDutchAuction.DA_PriceLimitExceeded.selector);
    auction.bid(aliceAcc, liquidator2, percentageToBid * 10 / 9, int(cashFromLiquidator1) - 100, 0);
    vm.stopPrank();
  }

  function test_BMAfterLiquidation() public {
    // start liquidation on acc1, discount = 20%
    IDutchAuction.AuctionParams memory params = getDefaultAuctionParam();
    params.startingMtMPercentage = 0.8e18;
    params.liquidatorFeeRate = 0;
    params.bufferMarginPercentage = 0.05e18;
    auction.setAuctionParams(params);

    markets["weth"].spotFeed.setHeartbeat(1 hours);
    markets["weth"].perpFeed.setHeartbeat(1 hours);

    _setSpotPrice("weth", 1000e18, 1e18);
    _setPerpPrice("weth", 1000e18, 1e18);

    uint acc1 = subAccounts.createAccountWithApproval(alice, address(this), srm);
    uint acc2 = subAccounts.createAccountWithApproval(bob, address(this), srm);

    _depositCash(alice, acc1, 65e18);
    _depositCash(bob, acc2, 65e18);

    _tradePerp(acc1, acc2); // acc1 short, acc2 long

    // both accounts have MtM = 65, IM = 0, MM = 15 now
    assertEq(getAccMaintenanceMargin(acc1), 15e18);

    // price increases, acc1 is underwater
    _setSpotPrice("weth", 1035e18, 1e18);
    _setPerpPrice("weth", 1035e18, 1e18);

    (int mm, int mtm) = srm.getMarginAndMarkToMarket(acc1, false, 0);
    assertEq(mm, -21.75e18);
    assertEq(mtm, 30e18);

    auction.startAuction(acc1, 0);

    // BM = -21.75 + (0.05 * -51.75) = -24.33
    assertApproxEqAbs(_getBufferMM(acc1), -24.33e18, 1e16);

    uint f_max = auction.getMaxProportion(acc1, 0);
    assertEq(f_max / 1e14, 5034);

    // Alice bids 10%
    vm.prank(alice);
    auction.bid(acc1, aliceAcc, 0.1e18, 0, 0);

    // Bob bids remaining 40.34% / 0.9 == 44.83%
    vm.prank(bob);
    (uint finalPercentage,,) = auction.bid(acc1, bobAcc, 1e18, 0, 0);
    assertEq(finalPercentage / 1e14, 4483);

    // Buffer margin after liquidating all is close to 0
    assertEq(_getBufferMM(acc1) / 1e10, 0);
  }

  /// Test that
  function testBufferMarginReservedCashCondition() public {
    _tradeCall(aliceAcc, bobAcc);
    _refreshOracles(2600e18);

    uint charlieAcc = subAccounts.createAccount(charlie, srm);
    _depositCash(charlie, charlieAcc, 101e18);

    address sean = address(0x9999);
    uint seanAcc = subAccounts.createAccount(sean, srm);

    // Make buffer margin large, for easy computation
    _setAuctionParamsWithBufferMargin(0.8e18);

    // setup initial env: MtM = 6000, MM = -10000, BM = -13200, discount = 0.2
    auction.startAuction(aliceAcc, 0);

    {
      (int mm, int bm, int mtm) = auction.getMarginAndMarkToMarket(aliceAcc, 0);
      assertApproxEqAbs(mm, -108e18, 1e18);
      assertApproxEqAbs(bm, -264e18, 1e18);
      assertApproxEqAbs(mtm, 86.9e18, 1e18);
    }

    // fast forward to all the way to the end of fast auction
    vm.warp(block.timestamp + _getDefaultAuctionParams().fastAuctionLength);
    _refreshOracles(2600e18);

    // discount should be 20%
    assertApproxEqAbs(auction.getCurrentBidPrice(aliceAcc), 69e18, 1e18);

    // Alice liquidates 30% of the portfolio
    vm.prank(charlie);
    {
      (uint finalPercentage, uint cashFromCharlie,) = auction.bid(aliceAcc, charlieAcc, 0.3e18, 0, 0);

      assertEq(finalPercentage, 0.3e18);
      assertApproxEqAbs(cashFromCharlie, 20e18, 1e18); // 30% of portfolio, priced at ~20

      (int mm, int bm, int mtm) = auction.getMarginAndMarkToMarket(aliceAcc, 0);
      assertApproxEqAbs(mm, -54e18, 1e18);
      assertApproxEqAbs(bm, -164e18, 1e18);
      assertApproxEqAbs(mtm, 82e18, 1e18);
      IDutchAuction.Auction memory auctionStruct = auction.getAuction(aliceAcc);
      assertApproxEqAbs(auctionStruct.reservedCash, 20e18, 1e18);

      int bidPrice = auction.getCurrentBidPrice(aliceAcc);
      // bid price drops from 69 -> 48 as only 70% of the remaining portfolio exists
      assertApproxEqAbs(bidPrice, 48e18, 1e18);
    }

    // require ((|bm - reservedCash|)) + bidPrice
    // collateral requirement == (-(-163.9 - 20.8)) * 0.142) == 26.22
    // bid price = 48 * 0.142 = 6.9
    // total cash required ~= 33.1

    // sean will liquidate 10%, so they need just over $33
    // add just a bit below to see if it reverts
    _depositCash(sean, seanAcc, 33e18);
    vm.prank(sean);
    {
      // didn't have enough, so it reverts
      vm.expectRevert(IDutchAuction.DA_InsufficientCash.selector);
      auction.bid(aliceAcc, seanAcc, 0.142e18, 0, 0);
    }

    // add $1, should work now
    _depositCash(sean, seanAcc, 1e18);

    vm.prank(sean);
    {
      (uint finalPercentage, uint cashFromSean,) = auction.bid(aliceAcc, seanAcc, 0.142e18, 0, 0);
      assertEq(finalPercentage, 0.142e18);
      assertApproxEqAbs(cashFromSean, 6.9e18, 0.1e18);
    }
  }

  function _getBufferMM(uint acc) internal view returns (int bufferMargin) {
    (int mm, int mtm) = srm.getMarginAndMarkToMarket(acc, false, 0);
    int mmBuffer = mm - mtm; // a negative number added to the mtm to become maintenance margin

    IDutchAuction.AuctionParams memory params = auction.getAuctionParams();

    bufferMargin = mm + (mmBuffer * int(params.bufferMarginPercentage) / 1e18);
  }
}
