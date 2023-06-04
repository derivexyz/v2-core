// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "test/shared/utils/JsonMechIO.sol";
import "./util/LiquidationSimBase.sol";

contract LiquidationSimTests is LiquidationSimBase {
  using stdJson for string;

  function testLiquidationSim1() public {
    runLiquidationSim("Test1");
  }

  function testLiquidationSim2() public {
    runLiquidationSim("Test2");
  }

  function testLiquidationSim3() public {
    runLiquidationSim("Test3");
  }

  function testLiquidationSim4() public {
    runLiquidationSim("Test4");
  }
  // TODO:
  //  function testLiquidationSim5() public {
  //    runLiquidationSim("Test5");
  //  }
  //
  //  function testLiquidationSim6() public {
  //    runLiquidationSim("Test6");
  //  }

  function runLiquidationSim(string memory testName) internal {
    LiquidationSim memory data = LiquidationSimBase.getTestData(testName);
    setupTestScenario(data);

    vm.warp(data.StartTime);
    startAuction();

    for (uint i = 0; i < data.Actions.length; ++i) {
      // console2.log("\n=== STEP:", i);
      updateToActionState(data, i);
      checkPreLiquidation(data, i);
      doLiquidation(data, i);
      checkPostLiquidation(data, i);
    }
  }

  function startAuction() internal {
    uint worstScenario = getWorstScenario(aliceAcc);
    auction.startAuction(aliceAcc, worstScenario);
  }

  function doLiquidation(LiquidationSim memory data, uint actionId) internal {
    uint liqAcc = subAccounts.createAccount(address(this), IManager(address(pmrm)));
    _depositCash(liqAcc, 1000000000e18);

    (uint finalPercentage, uint cashFromBidder, uint cashToBidder) =
      auction.bid(aliceAcc, liqAcc, data.Actions[actionId].Liquidator.PercentLiquidated);

    if (data.Actions[actionId].Results.ExpectedBidPrice < 0) {
      // insolvent
      assertApproxEqAbs(int(cashToBidder), -data.Actions[actionId].Results.ExpectedBidPrice, 1e6, "bid price insolvent");
    } else {
      assertApproxEqAbs(int(cashFromBidder), data.Actions[actionId].Results.ExpectedBidPrice, 1e6, "bid price solvent");
    }

    // TODO: % of remaining assets received?
    assertApproxEqAbs(finalPercentage, data.Actions[actionId].Results.LiquidatedOfOriginal, 1e6, "final percentage");
  }

  function checkPreLiquidation(LiquidationSim memory data, uint actionId) internal {
    uint worstScenario = getWorstScenario(aliceAcc);
    (int mm, int bm, int mtm) = auction.getMarginAndMarkToMarket(aliceAcc, worstScenario);
    uint fMax = auction.getMaxProportion(aliceAcc, worstScenario);

    assertApproxEqAbs(mtm, data.Actions[actionId].Results.PreMtM, 1e6, "pre mtm");
    assertApproxEqAbs(mm, data.Actions[actionId].Results.PreMM, 1e6, "pre mm");
    assertApproxEqAbs(bm, data.Actions[actionId].Results.PreBM, 1e6, "pre bm");
    assertApproxEqAbs(fMax, data.Actions[actionId].Results.PreFMax, 1e6, "pre fmax");
  }

  function checkPostLiquidation(LiquidationSim memory data, uint actionId) internal {
    uint worstScenario = getWorstScenario(aliceAcc);
    (int mm, int bm, int mtm) = auction.getMarginAndMarkToMarket(aliceAcc, worstScenario);
    uint fMax = auction.getMaxProportion(aliceAcc, worstScenario);

    assertApproxEqAbs(mtm, data.Actions[actionId].Results.PostMtM, 1e6, "post mtm");
    assertApproxEqAbs(mm, data.Actions[actionId].Results.PostMM, 1e6, "post mm");
    assertApproxEqAbs(bm, data.Actions[actionId].Results.PostBM, 1e6, "post bm");
    assertApproxEqAbs(fMax, data.Actions[actionId].Results.PostFMax, 1e6, "post fmax");
  }

  function getWorstScenario(uint account) internal view returns (uint worstScenario) {
    worstScenario = 0;
    int worstMM = 0;
    for (uint i = 0; i < pmrm.getScenarios().length; ++i) {
      (int mm_,,) = auction.getMarginAndMarkToMarket(account, i);
      if (mm_ < worstMM) {
        worstMM = mm_;
        worstScenario = i;
      }
    }
  }

  function updateToActionState(LiquidationSim memory data, uint actionId) internal {
    vm.warp(data.Actions[actionId].Time);
    updateFeeds(data.Actions[actionId].Feeds);
  }
}
