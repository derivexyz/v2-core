// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "test/shared/utils/JsonMechIO.sol";
import "test/risk-managers/unit-tests/PMRM/utils/PMRMTestBase.sol";

import "lyra-utils/encoding/OptionEncoding.sol";

contract TempReader {
  function readInt(string memory json, string memory location) external pure returns (int) {
    return stdJson.readInt(json, location);
  }
}

contract LiquidationSimBase is PMRMTestBase {
  using stdJson for string;

  struct LiquidationSim {
    uint StartTime;
    bool IsForce;
    Portfolio InitialPortfolio;
    LiquidationAction[] Actions;
  }

  struct Portfolio {
    int Cash;
    int PerpPosition;
    int BasePosition;
    uint[] OptionStrikes;
    uint[] OptionExpiries;
    uint[] OptionIsCall;
    int[] OptionAmounts;
    Feeds initialFeeds;
  }

  struct LiquidationAction {
    uint Time;
    Feeds Feeds;
    Liquidator Liquidator;
    Results Results;
  }

  struct Feeds {
    uint StablePrice;
    uint StableConfidence;
    uint SpotPrice;
    uint SpotConfidence;
    uint[] FeedExpiries;
    uint[] Forwards;
    uint[] ForwardConfidences;
    int[] Rates;
    uint[] RateConfidences;
    uint[] VolFeedStrikes;
    uint[] VolFeedExpiries;
    uint[] VolFeedVols;
  }

  struct Liquidator {
    uint PercentLiquidated;
  }

  struct Results {
    int PreMtM;
    int PreMM;
    int PreBM;
    uint PreFMax;
    int ExpectedBidPrice;
    uint FinalPercentageReceived;
    uint LiquidatedOfOriginal;
    int PostMtM;
    int PostMM;
    int PostBM;
    uint PostFMax;
    int SMPayout;
  }

  TempReader t;

  constructor() {
    t = new TempReader();
  }

  function getTestData(string memory fileName, string memory testName) internal view returns (LiquidationSim memory sim) {
    testName = string.concat(".", testName);
    string memory json = JsonMechIO.jsonFromRelPath(string.concat("/test/integration-tests/liquidation/", fileName, ".json"));
    sim.StartTime = json.readUint(string.concat(testName, ".StartTime"));
    sim.IsForce = json.readBool(string.concat(testName, ".IsForce"));
    sim.InitialPortfolio.Cash = json.readInt(string.concat(testName, ".InitialPortfolio.Cash"));
    sim.InitialPortfolio.PerpPosition = json.readInt(string.concat(testName, ".InitialPortfolio.Perps"));
    sim.InitialPortfolio.BasePosition = json.readInt(string.concat(testName, ".InitialPortfolio.Base"));
    sim.InitialPortfolio.OptionStrikes = json.readUintArray(string.concat(testName, ".InitialPortfolio.OptionStrikes"));
    sim.InitialPortfolio.OptionExpiries =
      json.readUintArray(string.concat(testName, ".InitialPortfolio.OptionExpiries"));
    sim.InitialPortfolio.OptionIsCall = json.readUintArray(string.concat(testName, ".InitialPortfolio.OptionIsCall"));
    sim.InitialPortfolio.OptionAmounts = json.readIntArray(string.concat(testName, ".InitialPortfolio.OptionAmounts"));

    sim.InitialPortfolio.initialFeeds.StablePrice =
      json.readUint(string.concat(testName, ".InitialPortfolio.StablePrice"));
    // TODO: no stable confidence
    sim.InitialPortfolio.initialFeeds.StableConfidence = 1e18;
    sim.InitialPortfolio.initialFeeds.SpotPrice = json.readUint(string.concat(testName, ".InitialPortfolio.SpotPrice"));
    sim.InitialPortfolio.initialFeeds.SpotConfidence =
      json.readUint(string.concat(testName, ".InitialPortfolio.SpotConfidence"));
    sim.InitialPortfolio.initialFeeds.FeedExpiries =
      json.readUintArray(string.concat(testName, ".InitialPortfolio.FeedExpiries"));
    sim.InitialPortfolio.initialFeeds.Forwards =
      json.readUintArray(string.concat(testName, ".InitialPortfolio.Forwards"));
    sim.InitialPortfolio.initialFeeds.ForwardConfidences =
      json.readUintArray(string.concat(testName, ".InitialPortfolio.ForwardConfidences"));
    sim.InitialPortfolio.initialFeeds.Rates = json.readIntArray(string.concat(testName, ".InitialPortfolio.Rates"));
    sim.InitialPortfolio.initialFeeds.RateConfidences =
      json.readUintArray(string.concat(testName, ".InitialPortfolio.RateConfidences"));
    sim.InitialPortfolio.initialFeeds.VolFeedStrikes =
      json.readUintArray(string.concat(testName, ".InitialPortfolio.OptionStrikes"));
    sim.InitialPortfolio.initialFeeds.VolFeedExpiries =
      json.readUintArray(string.concat(testName, ".InitialPortfolio.OptionExpiries"));
    sim.InitialPortfolio.initialFeeds.VolFeedVols =
      json.readUintArray(string.concat(testName, ".InitialPortfolio.OptionVols"));

    // add actions
    uint actionCount = json.readUint(string.concat(testName, ".ActionCount"));
    sim.Actions = new LiquidationAction[](actionCount);
    for (uint i = 0; i < actionCount; i++) {
      sim.Actions[i] = getActionData(json, testName, i);
    }
    return sim;
  }

  function getActionData(string memory json, string memory testName, uint actionNum)
    internal
    view
    returns (LiquidationAction memory action)
  {
    // E.g. Test1.Actions[0]
    string memory baseActionIndex =
      string.concat(string.concat(string.concat(testName, ".Actions["), lookupNum(actionNum)), "]");

    action.Time = json.readUint(string.concat(baseActionIndex, ".Time"));
    action.Feeds.StablePrice = json.readUint(string.concat(baseActionIndex, ".PortfolioAndFeeds.StablePrice"));
    // TODO: no stable confidence
    action.Feeds.StableConfidence = 1e18;
    action.Feeds.SpotPrice = json.readUint(string.concat(baseActionIndex, ".PortfolioAndFeeds.SpotPrice"));
    action.Feeds.SpotConfidence = json.readUint(string.concat(baseActionIndex, ".PortfolioAndFeeds.SpotConfidence"));
    action.Feeds.FeedExpiries = json.readUintArray(string.concat(baseActionIndex, ".PortfolioAndFeeds.FeedExpiries"));
    action.Feeds.Forwards = json.readUintArray(string.concat(baseActionIndex, ".PortfolioAndFeeds.Forwards"));
    action.Feeds.ForwardConfidences =
      json.readUintArray(string.concat(baseActionIndex, ".PortfolioAndFeeds.ForwardConfidences"));
    action.Feeds.Rates = json.readIntArray(string.concat(baseActionIndex, ".PortfolioAndFeeds.Rates"));
    action.Feeds.RateConfidences =
      json.readUintArray(string.concat(baseActionIndex, ".PortfolioAndFeeds.RateConfidences"));
    action.Feeds.VolFeedStrikes = json.readUintArray(string.concat(baseActionIndex, ".PortfolioAndFeeds.OptionStrikes"));
    action.Feeds.VolFeedExpiries =
      json.readUintArray(string.concat(baseActionIndex, ".PortfolioAndFeeds.OptionExpiries"));
    action.Feeds.VolFeedVols = json.readUintArray(string.concat(baseActionIndex, ".PortfolioAndFeeds.OptionVols"));

    action.Liquidator.PercentLiquidated = json.readUint(string.concat(baseActionIndex, ".Liquidator.PercentWant"));
    action.Results.PreMtM = json.readInt(string.concat(baseActionIndex, ".Results.PreMtM"));
    action.Results.PreMM = json.readInt(string.concat(baseActionIndex, ".Results.PreMM"));
    action.Results.PreBM = json.readInt(string.concat(baseActionIndex, ".Results.PreBM"));
    action.Results.PreFMax = json.readUint(string.concat(baseActionIndex, ".Results.PreFMax"));
    action.Results.ExpectedBidPrice = json.readInt(string.concat(baseActionIndex, ".Results.ExpectedBidPrice"));
    action.Results.FinalPercentageReceived =
      json.readUint(string.concat(baseActionIndex, ".Results.FinalPercentageReceived"));
    action.Results.LiquidatedOfOriginal =
      json.readUint(string.concat(baseActionIndex, ".Results.fLiquidatedOfOriginal"));
    action.Results.PostMtM = json.readInt(string.concat(baseActionIndex, ".Results.PostMtM"));
    action.Results.PostMM = json.readInt(string.concat(baseActionIndex, ".Results.PostMM"));
    action.Results.PostBM = json.readInt(string.concat(baseActionIndex, ".Results.PostBM"));
    action.Results.PostFMax = json.readUint(string.concat(baseActionIndex, ".Results.PostFMax"));

    action.Results.SMPayout = getSMPayout(json, string.concat(baseActionIndex, ".Results.SMPayout"));

    return action;
  }

  function getSMPayout(string memory json, string memory location) internal view returns (int) {
    try t.readInt(json, location) returns (int payout) {
      return payout;
    } catch {
      return 0;
    }
  }

  function lookupNum(uint num) internal pure returns (string memory) {
    // return the string version of num
    if (num == 0) {
      return "0";
    } else if (num == 1) {
      return "1";
    } else if (num == 2) {
      return "2";
    } else if (num == 3) {
      return "3";
    } else if (num == 4) {
      return "4";
    } else if (num == 5) {
      return "5";
    } else if (num == 6) {
      return "6";
    }
    revert("out of lookupNums");
  }

  function setupTestScenario(LiquidationSim memory data) internal {
    vm.warp(data.StartTime);

    uint totalAssets = data.InitialPortfolio.OptionStrikes.length;

    totalAssets += data.InitialPortfolio.Cash != 0 ? 1 : 0;
    totalAssets += data.InitialPortfolio.PerpPosition != 0 ? 1 : 0;
    totalAssets += data.InitialPortfolio.BasePosition != 0 ? 1 : 0;

    ISubAccounts.AssetBalance[] memory balances = new ISubAccounts.AssetBalance[](totalAssets);

    uint i = 0;
    for (; i < data.InitialPortfolio.OptionStrikes.length; ++i) {
      balances[i] = ISubAccounts.AssetBalance({
        asset: IAsset(option),
        subId: OptionEncoding.toSubId(
          data.InitialPortfolio.OptionExpiries[i],
          data.InitialPortfolio.OptionStrikes[i],
          data.InitialPortfolio.OptionIsCall[i] == 1
          ),
        balance: data.InitialPortfolio.OptionAmounts[i]
      });
    }

    if (data.InitialPortfolio.Cash != 0) {
      balances[i++] =
        ISubAccounts.AssetBalance({asset: IAsset(address(cash)), subId: 0, balance: data.InitialPortfolio.Cash});
    }
    if (data.InitialPortfolio.PerpPosition != 0) {
      balances[i++] = ISubAccounts.AssetBalance({
        asset: IAsset(address(mockPerp)),
        subId: 0,
        balance: data.InitialPortfolio.PerpPosition
      });
    }
    if (data.InitialPortfolio.BasePosition != 0) {
      balances[i++] = ISubAccounts.AssetBalance({
        asset: IAsset(address(baseAsset)),
        subId: 0,
        balance: data.InitialPortfolio.BasePosition
      });
      
    }

    setBalances(aliceAcc, balances);
    updateFeeds(data.InitialPortfolio.initialFeeds);
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
        uint64(feedData.VolFeedExpiries[i]), uint128(feedData.VolFeedStrikes[i]), feedData.VolFeedVols[i], 1e18
      );
    }
  }
}
