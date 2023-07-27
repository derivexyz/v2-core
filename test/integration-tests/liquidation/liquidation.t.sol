// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "lyra-utils/encoding/OptionEncoding.sol";

import "../shared/IntegrationTestBase.t.sol";
import {IManager} from "../../../src/interfaces/IManager.sol";

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

  function testLiquidationCannotBeFrontRun() public {
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
    (uint finalPercentage1, uint cashFromLiquidator1,) = auction.bid(aliceAcc, liquidator1, percentageToBid);
    assertEq(finalPercentage1, percentageToBid);

    // liquidator 2 also bid 30%, but it is executed after liquidator 1
    (uint finalPercentage2, uint cashFromLiquidator2,) = auction.bid(aliceAcc, liquidator2, percentageToBid);
    assertEq(finalPercentage2, percentageToBid);
    assertEq(cashFromLiquidator1, cashFromLiquidator2);

    vm.stopPrank();
  }
}
