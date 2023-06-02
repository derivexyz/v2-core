// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "test/shared/utils/JsonMechIO.sol";
import "./util/LiquidationSimBase.sol";

contract LiquidationSimTests is LiquidationSimBase {
  using stdJson for string;

  function testLiquidationSim() public {
    LiquidationSim memory data = LiquidationSimBase.getTestData("Test2");
    ISubAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(data);
    setBalances(aliceAcc, balances);
    updateToActionState(data, 0);

    vm.warp(data.StartTime);
    startAuction(aliceAcc);

    for (uint i = 0; i < data.Actions.length; ++i) {
      // console2.log("\n=== STEP:", i);
      updateToActionState(data, i);
      checkPreLiquidation(data, i);
      doLiquidation(data, i);
      checkPostLiquidation(data, i);
    }
  }

  function startAuction(uint accountId) internal {
    // console2.log("Start auction");
    uint worstScenario = getWorstScenario(accountId);
    auction.startAuction(accountId, worstScenario);
  }

  function doLiquidation(LiquidationSim memory data, uint actionId) internal {
    // console2.log("\n-Do liquidation", actionId);

    uint liqAcc = subAccounts.createAccount(address(this), IManager(address(pmrm)));
    _depositCash(liqAcc, data.Actions[actionId].Liquidator.CashBalance);
    // (uint finalPercentage, uint cashFromBidder, uint cashToBidder) =
    auction.bid(aliceAcc, liqAcc, data.Actions[actionId].Liquidator.PercentLiquidated);
    // console2.log("finalPercentage", finalPercentage);
    // console2.log("cashFromBidder", cashFromBidder);
    // console2.log("cashToBidder", cashToBidder);
  }

  function checkPreLiquidation(LiquidationSim memory data, uint actionId) internal {
    // console2.log("\n-Pre check", actionId);

    uint worstScenario = getWorstScenario(aliceAcc);
    (int mm, int bm, int mtm) = auction.getMarginAndMarkToMarket(aliceAcc, worstScenario);
    // console2.log("Worst Scenario", worstScenario);
    // console2.log("Worst MM", mm);
    // console2.log("Worst BM", bm);
    // console2.log("Worst MTM", mtm);
    // console2.log("max portion", auction.getMaxProportion(aliceAcc, worstScenario));
    // TODO: check all results
    assertApproxEqAbs(mtm, data.Actions[actionId].Results.PreMtM, 1e6);
  }

  function checkPostLiquidation(LiquidationSim memory data, uint actionId) internal {
    // console2.log("\n-Post check", actionId);

    uint worstScenario = getWorstScenario(aliceAcc);
    (int mm, int bm, int mtm) = auction.getMarginAndMarkToMarket(aliceAcc, worstScenario);
    // console2.log("Worst Scenario", worstScenario);
    // console2.log("Worst MM", mm);
    // console2.log("Worst BM", bm);
    // console2.log("Worst MTM", mtm);
    // console2.log("max portion", auction.getMaxProportion(aliceAcc, worstScenario));
    assertApproxEqAbs(mtm, data.Actions[actionId].Results.PostMtM, 1e6);
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

  function updateFeeds(Feeds memory feedData) internal {
    stableFeed.setSpot(feedData.StablePrice, feedData.StableConfidence);
    feed.setSpot(feedData.SpotPrice, feedData.SpotConfidence);

    for (uint i = 0; i < feedData.FeedExpiries.length; i++) {
      feed.setForwardPrice(feedData.FeedExpiries[i], feedData.Forwards[i], feedData.ForwardConfidences[i]);
      feed.setInterestRate(feedData.FeedExpiries[i], int64(feedData.Rates[i]), uint64(feedData.RateConfidences[i]));
    }

    for (uint i = 0; i < feedData.VolFeedStrikes.length; ++i) {
      feed.setVol(
        uint64(feedData.VolFeedExpiries[i]),
        uint128(feedData.VolFeedStrikes[i]),
        uint128(feedData.VolFeedVols[i]),
        uint64(1e18)
      );
    }
  }
}
