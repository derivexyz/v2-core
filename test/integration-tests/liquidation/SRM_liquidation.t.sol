// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "lyra-utils/encoding/OptionEncoding.sol";

import "../shared/IntegrationTestBase.t.sol";

import {getDefaultAuctionParam} from "../../../scripts/config.sol";
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
    (uint finalPercentage1, uint cashFromLiquidator1,) = auction.bid(aliceAcc, liquidator1, percentageToBid, 0);
    assertEq(finalPercentage1, percentageToBid);

    // liquidator 2 also bid 30%, but it is executed after liquidator 1
    (uint finalPercentage2, uint cashFromLiquidator2,) = auction.bid(aliceAcc, liquidator2, percentageToBid, 0);
    assertEq(finalPercentage2, percentageToBid);
    assertEq(cashFromLiquidator1, cashFromLiquidator2);

    vm.stopPrank();
  }

  function testCannotMakeBidderPayMoreThanMaxCash() public {
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
    (uint finalPercentage1, uint cashFromLiquidator1,) = auction.bid(aliceAcc, liquidator1, percentageToBid, 0);
    assertEq(finalPercentage1, percentageToBid);
    vm.stopPrank();

    // before liquidator 2 bids, alice deposit more cash to her account, making liquidator 2's bid revert
    _depositCash(alice, aliceAcc, 50e18);

    // bid reverts
    vm.startPrank(charlie);
    vm.expectRevert(IDutchAuction.DA_MaxCashExceeded.selector);
    auction.bid(aliceAcc, liquidator2, percentageToBid, cashFromLiquidator1);
    vm.stopPrank();
  }

  function test_BMAfterLiquidation() public {
    // start liquidation on acc1, discount = 20%
    IDutchAuction.SolventAuctionParams memory params = getDefaultAuctionParam();
    params.startingMtMPercentage = 0.8e18;
    params.liquidatorFeeRate = 0;
    auction.setSolventAuctionParams(params);
    auction.setBufferMarginPercentage(0.05e18);
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
    assertEq(_getBufferMM(acc1) / 1e16, -2433);

    uint f_max = auction.getMaxProportion(acc1, 0);
    assertEq(f_max / 1e14, 5034);

    // Alice bids 10%
    vm.prank(alice);
    auction.bid(acc1, aliceAcc, 0.1e18, 0);

    // Bob bids remaining 40.34%
    vm.prank(bob);
    (uint finalPercentage,,) = auction.bid(acc1, bobAcc, f_max, 0);
    assertEq(finalPercentage / 1e14, 4034);

    // Buffer margin after liquidating all is close to 0
    assertEq(_getBufferMM(acc1) / 1e10, 0);
  }

  function _getBufferMM(uint acc) internal view returns (int bufferMargin) {
    (int mm, int mtm) = srm.getMarginAndMarkToMarket(acc, false, 0);
    int mmBuffer = mm - mtm; // a negative number added to the mtm to become maintenance margin

    bufferMargin = mm + (mmBuffer * auction.bufferMarginPercentage() / 1e18);
  }
}