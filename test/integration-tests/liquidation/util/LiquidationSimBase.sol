// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "test/shared/utils/JsonMechIO.sol";
import "test/risk-managers/unit-tests/PMRM/utils/PMRMTestBase.sol";

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
    uint[] OptionExpiry;
    bool[] OptionIsCall;
    int[] OptionAmount;
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
    uint CashBalance;
    uint PercentLiquidated;
  }

  struct Results {
    int PreMtM;
    int PreMM;
    int PreBM;
    uint PreFMax;
    int ExpectedBidPrice;
    uint FinalPercentageReceived;
    int PostMtM;
    int PostMM;
    int PostBM;
    uint PostFMax;
  }

  function getTestData(string memory testName) internal view returns (LiquidationSim memory sim) {
    testName = string.concat(".", testName);
    string memory json = JsonMechIO.jsonFromRelPath("/test/integration-tests/liquidation/liquidationTests.json");
    sim.StartTime = json.readUint(string.concat(testName, ".StartTime"));
    sim.IsForce = json.readBool(string.concat(testName, ".IsForce"));
    sim.InitialPortfolio.Cash = json.readInt(string.concat(testName, ".InitialPortfolio.Cash"));
    sim.InitialPortfolio.PerpPosition = json.readInt(string.concat(testName, ".InitialPortfolio.PerpPosition"));
    sim.InitialPortfolio.BasePosition = json.readInt(string.concat(testName, ".InitialPortfolio.BasePosition"));
    sim.InitialPortfolio.OptionStrikes = json.readUintArray(string.concat(testName, ".InitialPortfolio.OptionStrikes"));
    sim.InitialPortfolio.OptionExpiry = json.readUintArray(string.concat(testName, ".InitialPortfolio.OptionExpiry"));
    sim.InitialPortfolio.OptionIsCall = json.readBoolArray(string.concat(testName, ".InitialPortfolio.OptionIsCall"));
    sim.InitialPortfolio.OptionAmount = json.readIntArray(string.concat(testName, ".InitialPortfolio.OptionAmount"));

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
    pure
    returns (LiquidationAction memory action)
  {
    // E.g. Test1.Actions[0]
    string memory baseActionIndex =
      string.concat(string.concat(string.concat(testName, ".Actions["), lookupNum(actionNum)), "]");

    action.Time = json.readUint(string.concat(baseActionIndex, ".Time"));
    action.Feeds.StablePrice = json.readUint(string.concat(baseActionIndex, ".Feeds.StablePrice"));
    action.Feeds.StableConfidence = json.readUint(string.concat(baseActionIndex, ".Feeds.StableConfidence"));
    action.Feeds.SpotPrice = json.readUint(string.concat(baseActionIndex, ".Feeds.SpotPrice"));
    action.Feeds.SpotConfidence = json.readUint(string.concat(baseActionIndex, ".Feeds.SpotConfidence"));
    action.Feeds.FeedExpiries = json.readUintArray(string.concat(baseActionIndex, ".Feeds.FeedExpiries"));
    action.Feeds.Forwards = json.readUintArray(string.concat(baseActionIndex, ".Feeds.Forwards"));
    action.Feeds.ForwardConfidences = json.readUintArray(string.concat(baseActionIndex, ".Feeds.ForwardConfidences"));
    action.Feeds.Rates = json.readIntArray(string.concat(baseActionIndex, ".Feeds.Rates"));
    action.Feeds.RateConfidences = json.readUintArray(string.concat(baseActionIndex, ".Feeds.RateConfidences"));
    action.Feeds.VolFeedStrikes = json.readUintArray(string.concat(baseActionIndex, ".Feeds.VolFeedStrikes"));
    action.Feeds.VolFeedExpiries = json.readUintArray(string.concat(baseActionIndex, ".Feeds.VolFeedExpiries"));
    action.Feeds.VolFeedVols = json.readUintArray(string.concat(baseActionIndex, ".Feeds.VolFeedVols"));
    action.Liquidator.CashBalance = json.readUint(string.concat(baseActionIndex, ".Liquidator.CashBalance"));
    action.Liquidator.PercentLiquidated = json.readUint(string.concat(baseActionIndex, ".Liquidator.PercentLiquidated"));
    action.Results.PreMtM = json.readInt(string.concat(baseActionIndex, ".Results.PreMtM"));
    action.Results.PreMM = json.readInt(string.concat(baseActionIndex, ".Results.PreMM"));
    action.Results.PreBM = json.readInt(string.concat(baseActionIndex, ".Results.PreBM"));
    action.Results.PreFMax = json.readUint(string.concat(baseActionIndex, ".Results.PreFMax"));
    action.Results.ExpectedBidPrice = json.readInt(string.concat(baseActionIndex, ".Results.ExpectedBidPrice"));
    action.Results.FinalPercentageReceived =
      json.readUint(string.concat(baseActionIndex, ".Results.FinalPercentageReceived"));
    action.Results.PostMtM = json.readInt(string.concat(baseActionIndex, ".Results.PostMtM"));
    action.Results.PostMM = json.readInt(string.concat(baseActionIndex, ".Results.PostMM"));
    action.Results.PostBM = json.readInt(string.concat(baseActionIndex, ".Results.PostBM"));
    action.Results.PostFMax = json.readUint(string.concat(baseActionIndex, ".Results.PostFMax"));

    return action;
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


  function setupTestScenarioAndGetAssetBalances(LiquidationSim memory data)
  internal
  returns (ISubAccounts.AssetBalance[] memory balances)
  {
    vm.warp(data.StartTime);

    uint totalAssets = data.InitialPortfolio.OptionStrikes.length;

    totalAssets += data.InitialPortfolio.Cash != 0 ? 1 : 0;
    totalAssets += data.InitialPortfolio.PerpPosition != 0 ? 1 : 0;
    totalAssets += data.InitialPortfolio.BasePosition != 0 ? 1 : 0;

    balances = new ISubAccounts.AssetBalance[](totalAssets);

    uint i = 0;
    for (; i < data.InitialPortfolio.OptionStrikes.length; ++i) {
      balances[i] = ISubAccounts.AssetBalance({
      asset: IAsset(option),
      subId: OptionEncoding.toSubId(
          data.InitialPortfolio.OptionExpiry[i],
          data.InitialPortfolio.OptionStrikes[i],
          data.InitialPortfolio.OptionIsCall[i]
        ),
      balance: data.InitialPortfolio.OptionAmount[i]
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

    return balances;
  }
}
