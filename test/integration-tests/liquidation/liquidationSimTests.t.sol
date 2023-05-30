
import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "test/shared/utils/JsonMechIO.sol";
import "./util/LiquidationPMRMTestBase.sol";


contract LiquidationSimTests is LiquidationPMRMTestBase {
  using stdJson for string;

  function testLiquidationSim() public {
    LiquidationSim memory data = LiquidationSimLoading.getTestData("Test2");
    ISubAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(data);
    setBalances(aliceAcc, balances);
    updateToActionState(data, 0);
    checkPreLiquidation(data, 0);

    vm.warp(data.StartTime);
    startAuction(aliceAcc);

    for (uint i=0; i<data.Actions.length; ++i) {
      console2.log("\n=== STEP:", i);
      updateToActionState(data, i);
      checkPreLiquidation(data, i);
      doLiquidation(data, i);
      checkPostLiquidation(data, i);
    }
  }

  function startAuction(uint accountId) internal {
    console2.log("Start auction");
    uint worstScenario = getWorstScenario(aliceAcc);
    auction.startAuction(aliceAcc, worstScenario);
  }

  function doLiquidation(LiquidationSim memory data, uint auctionId) internal {
    console2.log("\n-Do liquidation", auctionId);

    address liquidator = address(uint160(2**60 + auctionId));
    uint liqAcc = _setupAccount(liquidator);
    _depositCash(liqAcc, data.Actions[auctionId].Liquidator.CashBalance);
    vm.startPrank(liquidator);
    (uint finalPercentage, uint cashFromBidder, uint cashToBidder) = auction.bid(aliceAcc, liqAcc, data.Actions[auctionId].Liquidator.PercentLiquidated);
    console2.log("finalPercentage", finalPercentage);
    console2.log("cashFromBidder", cashFromBidder);
    console2.log("cashToBidder", cashToBidder);
  }

  function checkPreLiquidation(LiquidationSim memory data, uint auctionId) internal {
    console2.log("\n-Pre check", auctionId);

    uint worstScenario = getWorstScenario(aliceAcc);
    (int mm, int bm, int mtm) = auction.getMarginAndMarkToMarket(aliceAcc, worstScenario);
    console2.log("Worst Scenario", worstScenario);
    console2.log("Worst MM", mm);
    console2.log("Worst BM", bm);
    console2.log("Worst MTM", mtm);
    console2.log("max prorton", auction.getMaxProportion(aliceAcc, worstScenario));
  }

  function checkPostLiquidation(LiquidationSim memory data, uint auctionId) internal {
    console2.log("\n-Post check", auctionId);

    uint worstScenario = getWorstScenario(aliceAcc);
    (int mm, int bm, int mtm) = auction.getMarginAndMarkToMarket(aliceAcc, worstScenario);
    console2.log("Worst Scenario", worstScenario);
    console2.log("Worst MM", mm);
    console2.log("Worst BM", bm);
    console2.log("Worst MTM", mtm);
    console2.log("max prorton", auction.getMaxProportion(aliceAcc, worstScenario));
  }

  function getWorstScenario(uint account) internal returns (uint worstScenario) {
    worstScenario = 0;
    int worstMM = 0;
    for (uint i=0; i<pmrm.getScenarios().length; ++i) {
      (int mm_,,) = auction.getMarginAndMarkToMarket(aliceAcc, i);
      if (mm_ < worstMM){
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