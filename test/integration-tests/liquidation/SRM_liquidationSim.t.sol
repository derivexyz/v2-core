// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "lyra-utils/encoding/OptionEncoding.sol";

import "../shared/IntegrationTestBase.t.sol";

import {getDefaultAuctionParam} from "../../../scripts/config-local.sol";
import "./util/SRMLiquidationSimBase.sol";
/**
 * @dev testing liquidation process
 */

contract SRMLiqudationSimulationTests is SRMLiquidationSimBase {
  using stdJson for string;

  function testSRMLiquidationSim1() public {
    runLiquidationSim("SRM_liquidation", "Test1");
  }
//
//  function testLiquidationSim2() public {
//    runLiquidationSim("PMRM_solvent", "Test2");
//  }
//
//  function testLiquidationSim3() public {
//    runLiquidationSim("PMRM_solvent", "Test3");
//  }
//
//  function testLiquidationSim4() public {
//    runLiquidationSim("PMRM_solvent", "Test4");
//  }
//
//  function testLiquidationSim5() public {
//    runLiquidationSim("PMRM_solvent", "Test5");
//  }
//
//  function testLiquidationSim6() public {
//    runLiquidationSim("PMRM_solvent", "Test6");
//  }


  function runLiquidationSim(string memory fileName, string memory testName) internal {
    LiquidationSim memory data = SRMLiquidationSimBase.getTestData(fileName, testName);
    setupTestScenario(data);


    vm.warp(data.StartTime);
    startAuction();

    for (uint i = 0; i < data.Actions.length; ++i) {
      console2.log("\n=== STEP:", i);
      updateToActionState(data, i);
      console2.log("Pre:", i);
      checkPreLiquidation(data, i);
      console2.log("Liq:", i);
      doLiquidation(data, i);
      console2.log("Post:", i);
      checkPostLiquidation(data, i);
    }
  }

  function startAuction() internal {
    auction.startAuction(aliceAcc, 0);

  }

  function doLiquidation(LiquidationSim memory data, uint actionId) internal {
    uint liqAcc = subAccounts.createAccount(address(this), IManager(address(manager)));
    _depositCash(liqAcc, 1000000000e18);

    (uint finalPercentage, uint cashFromBidder, uint cashToBidder) =
              auction.bid(aliceAcc, liqAcc, data.Actions[actionId].Liquidator.PercentLiquidated, 0, 0);

    IDutchAuction.Auction memory auctionDetails = auction.getAuction(aliceAcc);
    if (auctionDetails.insolvent) {
      assertApproxEqRel(int(cashToBidder), - data.Actions[actionId].Results.SMPayout, 0.001e18, "bid price insolvent");
    } else {
      assertApproxEqRel(int(cashFromBidder), data.Actions[actionId].Results.ExpectedBidPrice, 0.001e18, "bid price solvent");
      assertApproxEqRel(
        finalPercentage, data.Actions[actionId].Results.LiquidatedOfOriginal, 0.001e18, "liquidated of original"
      );
    }
  }

  function checkPreLiquidation(LiquidationSim memory data, uint actionId) internal {
    (int mm, int bm, int mtm) = auction.getMarginAndMarkToMarket(aliceAcc, 0);
    IDutchAuction.Auction memory auctionDetails = auction.getAuction(aliceAcc);
    if (auctionDetails.insolvent) {
      // todo: this needs to be changed to use MM as lower bound
      // assertApproxEqAbs(mm, data.Actions[actionId].Results.LowerBound, 1e6, "lowerbound");
    } else {
      uint fMax = auction.getMaxProportion(aliceAcc, 0);
      assertApproxEqRel(fMax, data.Actions[actionId].Results.PreFMax, 0.001e18, "pre fmax");
    }

    console2.log("MTM", mtm);

    assertApproxEqRel(mtm, data.Actions[actionId].Results.PreMtM, 0.001e18, "pre mtm");
    assertApproxEqRel(mm, data.Actions[actionId].Results.PreMM, 0.001e18, "pre mm");
    assertApproxEqRel(bm, data.Actions[actionId].Results.PreBM, 0.001e18, "pre bm");
  }

  function checkPostLiquidation(LiquidationSim memory data, uint actionId) internal {
    (int mm, int bm, int mtm) = auction.getMarginAndMarkToMarket(aliceAcc, 0);

    assertApproxEqRel(mtm, data.Actions[actionId].Results.PostMtM, 0.001e18, "post mtm");
    assertApproxEqRel(mm, data.Actions[actionId].Results.PostMM, 0.001e18, "post mm");

    if (SignedMath.abs(data.Actions[actionId].Results.PostBM) < 1e10 || SignedMath.abs(bm) < 1e10) {
      assertApproxEqAbs(SignedMath.abs(bm), 0, 1e8, "post bm dust check");
      assertApproxEqAbs(SignedMath.abs(data.Actions[actionId].Results.PostBM), 0, 1e8, "post bm dust check");
    } else {
      assertApproxEqRel(bm, data.Actions[actionId].Results.PostBM, 0.00001e18, "post bm");
    }

    IDutchAuction.Auction memory auctionDetails = auction.getAuction(aliceAcc);
    if (auctionDetails.insolvent) {} else {
      uint fMax = auction.getMaxProportion(aliceAcc, 0);
      if (data.Actions[actionId].Results.PostFMax < 1e10 || fMax < 1e10) {
        assertApproxEqAbs(fMax, 0, 1e8, "post fmax dust check");
        assertApproxEqAbs(data.Actions[actionId].Results.PostFMax, 0, 1e8, "post fmax dust check");
      } else {
        assertApproxEqRel(fMax, data.Actions[actionId].Results.PostFMax, 0.001e18, "post fmax");
      }
    }
  }

  function updateToActionState(LiquidationSim memory data, uint actionId) internal {
    vm.warp(data.Actions[actionId].Time);
    updateFeeds(data.Actions[actionId].Feeds);
  }
}
