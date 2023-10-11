pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "../../../../../src/risk-managers/PMRM.sol";
import "../../../../../src/assets/CashAsset.sol";
import "../../../../../src/SubAccounts.sol";
import "../../../../../src/interfaces/IManager.sol";
import "../../../../../src/interfaces/IAsset.sol";
import "../../../../../src/interfaces/ISubAccounts.sol";

import "../../../../shared/mocks/MockManager.sol";
import "../../../../shared/mocks/MockERC20.sol";
import "../../../../shared/mocks/MockAsset.sol";
import "../../../../shared/mocks/MockOptionAsset.sol";
import "../../../../shared/mocks/MockSM.sol";
import "../../../../shared/mocks/MockFeeds.sol";
import "../../../../shared/mocks/MockCash.sol";

import "../../../../risk-managers/mocks/MockDutchAuction.sol";
import "../../../../shared/utils/JsonMechIO.sol";

import "../../../../risk-managers/unit-tests/PMRM/utils/PMRMTestBase.sol";

import "forge-std/console2.sol";

contract PMRMSimTest is PMRMTestBase {
  using stdJson for string;

  struct OptionData {
    uint secToExpiry;
    uint strike;
    bool isCall;
    int amount;
    uint vol;
    uint volConfidence;
  }

  struct OtherAssets {
    uint count;
    int cashAmount;
    int perpAmount;
    uint baseAmount;
    int perpUnrealisedPNL;
    int perpUnrealisedFunding;
  }

  struct FeedData {
    uint perpPrice;
    uint perpConfidence;
    uint spotPrice;
    uint spotConfidence;
    uint stablePrice;
    uint stableConfidence;
    uint[] expiries;
    uint[] forwards;
    uint[] forwardsVariable;
    uint[] forwardsFixed;
    uint[] forwardConfidences;
    int[] rates;
    uint[] rateConfidences;
  }

  struct Result {
    int perpContingency;
    int baseContingency;
    int unrealisedPerpPNL;
    int unrealisedFunding;
    int optionContingency;
    int forwardContingency;
    int oracleContingency;
    int lossFactor;
    int cash;
    int portfolioMTM;
    int initialMarginHand;
    int maintenanceMarginHand;
    int initialMarginCalc;
    int maintenanceMarginCalc;
  }

  function readOptionData(string memory json, string memory testId) internal pure returns (OptionData[] memory) {
    uint[] memory expiries = json.readUintArray(string.concat(testId, ".Scenario.OptionExpiries"));
    uint[] memory strikes = json.readUintArray(string.concat(testId, ".Scenario.OptionStrikes"));
    uint[] memory isCall = json.readUintArray(string.concat(testId, ".Scenario.OptionIsCall"));
    int[] memory amounts = json.readIntArray(string.concat(testId, ".Scenario.OptionAmounts"));
    uint[] memory vols = json.readUintArray(string.concat(testId, ".Scenario.OptionVols"));
    uint[] memory confidences = json.readUintArray(string.concat(testId, ".Scenario.OptionVolConfidences"));

    OptionData[] memory data = new OptionData[](expiries.length);

    require(expiries.length == strikes.length, "strikes length mismatch");
    require(expiries.length == isCall.length, "isCall length mismatch");
    require(expiries.length == amounts.length, "amounts length mismatch");
    require(expiries.length == vols.length, "vols length mismatch");
    require(expiries.length == confidences.length, "confidences length mismatch");

    for (uint i = 0; i < expiries.length; ++i) {
      data[i] = OptionData({
        secToExpiry: expiries[i],
        strike: strikes[i],
        isCall: isCall[i] == 1,
        amount: amounts[i],
        vol: vols[i],
        volConfidence: confidences[i]
      });
    }

    return data;
  }

  function readOtherAssetData(string memory json, string memory testId) internal pure returns (OtherAssets memory) {
    uint count = 0;
    int cashAmount = json.readInt(string.concat(testId, ".Scenario.Cash"));
    if (cashAmount != 0) {
      count++;
    }
    int perpAmount = json.readInt(string.concat(testId, ".Scenario.Perps"));
    if (perpAmount != 0) {
      count++;
    }
    uint baseAmount = json.readUint(string.concat(testId, ".Scenario.Base"));
    if (baseAmount != 0) {
      count++;
    }

    return OtherAssets({
      count: count,
      cashAmount: cashAmount,
      perpAmount: perpAmount,
      baseAmount: baseAmount,
      perpUnrealisedPNL: json.readInt(string.concat(testId, ".Scenario.UnrealisedPerpPNL")),
      perpUnrealisedFunding: json.readInt(string.concat(testId, ".Scenario.UnrealisedFunding"))
    });
  }

  function readFeedData(string memory json, string memory testId) internal pure returns (FeedData memory feedData) {
    feedData.spotPrice = json.readUint(string.concat(testId, ".Scenario.SpotPrice"));
    feedData.spotConfidence = json.readUint(string.concat(testId, ".Scenario.SpotConfidence"));
    feedData.stablePrice = json.readUint(string.concat(testId, ".Scenario.StablePrice"));
    feedData.stableConfidence = json.readUint(string.concat(testId, ".Scenario.StableConfidence"));
    feedData.expiries = json.readUintArray(string.concat(testId, ".Scenario.FeedExpiries"));
    // TODO: this should only be variable and fixed
    feedData.forwards = json.readUintArray(string.concat(testId, ".Scenario.Forwards"));
    feedData.forwardsVariable = json.readUintArray(string.concat(testId, ".Scenario.ForwardsVariable"));
    feedData.forwardsFixed = json.readUintArray(string.concat(testId, ".Scenario.ForwardsFixed"));
    feedData.forwardConfidences = json.readUintArray(string.concat(testId, ".Scenario.ForwardConfidences"));
    feedData.rates = json.readIntArray(string.concat(testId, ".Scenario.Rates"));
    feedData.rateConfidences = json.readUintArray(string.concat(testId, ".Scenario.RateConfidences"));
    feedData.perpPrice = json.readUint(string.concat(testId, ".Scenario.PerpPrice"));
    feedData.perpConfidence = json.readUint(string.concat(testId, ".Scenario.PerpConfidence"));

    return feedData;
  }

  function readResults(string memory json, string memory testId) internal pure returns (Result memory) {
    return Result({
      perpContingency: json.readInt(string.concat(testId, ".Result.PerpContingency")),
      baseContingency: json.readInt(string.concat(testId, ".Result.BaseContingency")),
      unrealisedPerpPNL: json.readInt(string.concat(testId, ".Result.UnrealisedPerpPNL")),
      unrealisedFunding: json.readInt(string.concat(testId, ".Result.UnrealisedFunding")),
      optionContingency: json.readInt(string.concat(testId, ".Result.OptionContingency")),
      forwardContingency: json.readInt(string.concat(testId, ".Result.ForwardContingency")),
      oracleContingency: json.readInt(string.concat(testId, ".Result.OracleContingency")),
      lossFactor: json.readInt(string.concat(testId, ".Result.LossFactor")),
      cash: json.readInt(string.concat(testId, ".Result.Cash")),
      portfolioMTM: json.readInt(string.concat(testId, ".Result.PortfolioMTM")),
      initialMarginHand: json.readInt(string.concat(testId, ".Result.InitialMarginHand")),
      maintenanceMarginHand: json.readInt(string.concat(testId, ".Result.MaintenanceMarginHand")),
      initialMarginCalc: json.readInt(string.concat(testId, ".Result.InitialMarginCalc")),
      maintenanceMarginCalc: json.readInt(string.concat(testId, ".Result.MaintenanceMarginCalc"))
    });
  }

  function setupTestScenarioAndGetAssetBalances(string memory testId)
    internal
    returns (ISubAccounts.AssetBalance[] memory balances)
  {
    uint referenceTime = block.timestamp;
    string memory json = JsonMechIO.jsonFromRelPath("/test/risk-managers/unit-tests/PMRM/testScenarios.json");

    FeedData memory feedData = readFeedData(json, testId);
    OptionData[] memory optionData = readOptionData(json, testId);
    OtherAssets memory otherAssets = readOtherAssetData(json, testId);

    /// Set feed values
    feed.setSpot(feedData.spotPrice, feedData.spotConfidence);
    for (uint i = 0; i < feedData.expiries.length; i++) {
      uint expiry = referenceTime + uint(feedData.expiries[i]);
      feed.setForwardPrice(expiry, feedData.forwards[i], feedData.forwardConfidences[i]);
      feed.setInterestRate(expiry, int64(feedData.rates[i]), uint64(feedData.rateConfidences[i]));
    }

    stableFeed.setSpot(feedData.stablePrice, feedData.stableConfidence);
    mockPerp.setMockPerpPrice(feedData.perpPrice, feedData.perpConfidence);

    /// Get assets for user

    uint totalAssets = optionData.length + otherAssets.count;

    balances = new ISubAccounts.AssetBalance[](totalAssets);

    for (uint i = 0; i < optionData.length; ++i) {
      uint expiry = referenceTime + uint(optionData[i].secToExpiry);
      balances[i] = ISubAccounts.AssetBalance({
        asset: IAsset(option),
        subId: OptionEncoding.toSubId(expiry, uint(optionData[i].strike), optionData[i].isCall),
        balance: optionData[i].amount
      });

      feed.setVol(uint64(expiry), uint128(optionData[i].strike), optionData[i].vol, optionData[i].volConfidence);
    }

    if (otherAssets.cashAmount != 0) {
      balances[balances.length - otherAssets.count--] =
        ISubAccounts.AssetBalance({asset: IAsset(address(cash)), subId: 0, balance: otherAssets.cashAmount});
    }
    if (otherAssets.perpAmount != 0) {
      balances[balances.length - otherAssets.count--] =
        ISubAccounts.AssetBalance({asset: IAsset(address(mockPerp)), subId: 0, balance: otherAssets.perpAmount});
    }
    if (otherAssets.baseAmount != 0) {
      balances[balances.length - otherAssets.count--] =
        ISubAccounts.AssetBalance({asset: IAsset(address(baseAsset)), subId: 0, balance: int(otherAssets.baseAmount)});
    }
    return balances;
  }

  function setupTestScenarioAndVerifyResults(string memory testId)
    internal
    returns (ISubAccounts.AssetBalance[] memory balances)
  {
    uint referenceTime = block.timestamp;
    string memory json = JsonMechIO.jsonFromRelPath("/test/risk-managers/unit-tests/PMRM/testAndVerifyScenarios.json");

    FeedData memory feedData = readFeedData(json, testId);
    OptionData[] memory optionData = readOptionData(json, testId);
    OtherAssets memory otherAssets = readOtherAssetData(json, testId);

    /// Set feed values
    feed.setSpot(feedData.spotPrice, feedData.spotConfidence);
    for (uint i = 0; i < feedData.expiries.length; i++) {
      uint expiry = referenceTime + uint(feedData.expiries[i]);
      feed.setForwardPricePortions(
        expiry, feedData.forwardsFixed[i], feedData.forwardsVariable[i], feedData.forwardConfidences[i]
      );
      feed.setInterestRate(expiry, int64(feedData.rates[i]), uint64(feedData.rateConfidences[i]));
    }

    stableFeed.setSpot(feedData.stablePrice, feedData.stableConfidence);
    mockPerp.setMockPerpPrice(feedData.perpPrice, feedData.perpConfidence);
    /// Get assets for user

    uint totalAssets = optionData.length + otherAssets.count;

    balances = new ISubAccounts.AssetBalance[](totalAssets);

    for (uint i = 0; i < optionData.length; ++i) {
      uint expiry = referenceTime + uint(optionData[i].secToExpiry);
      balances[i] = ISubAccounts.AssetBalance({
        asset: IAsset(option),
        subId: OptionEncoding.toSubId(expiry, uint(optionData[i].strike), optionData[i].isCall),
        balance: optionData[i].amount
      });

      feed.setVol(uint64(expiry), uint128(optionData[i].strike), optionData[i].vol, optionData[i].volConfidence);
    }

    if (otherAssets.cashAmount != 0) {
      balances[balances.length - otherAssets.count--] =
        ISubAccounts.AssetBalance({asset: IAsset(address(cash)), subId: 0, balance: otherAssets.cashAmount});
    }
    if (otherAssets.perpAmount != 0) {
      balances[balances.length - otherAssets.count--] =
        ISubAccounts.AssetBalance({asset: IAsset(address(mockPerp)), subId: 0, balance: otherAssets.perpAmount});
    }
    if (otherAssets.baseAmount != 0) {
      balances[balances.length - otherAssets.count--] =
        ISubAccounts.AssetBalance({asset: IAsset(address(baseAsset)), subId: 0, balance: int(otherAssets.baseAmount)});
    }
    pmrm.setBalances(aliceAcc, balances);

    mockPerp.mockAccountPnlAndFunding(aliceAcc, otherAssets.perpUnrealisedFunding, otherAssets.perpUnrealisedPNL);

    verify(readResults(json, testId));
  }

  function verify(Result memory results) internal {
    IPMRM.Portfolio memory portfolio = pmrm.arrangePortfolio(aliceAcc);

    assertApproxEqAbs(portfolio.totalMtM, results.portfolioMTM - results.cash, 1e8, "Portfolio MTM");
    assertApproxEqAbs(portfolio.basisContingency, results.forwardContingency, 1e8, "Basis Contingency");
    assertApproxEqAbs(
      portfolio.staticContingency,
      uint(-(results.perpContingency + results.baseContingency + results.optionContingency)),
      1e8,
      "asset contingencies"
    );
    assertApproxEqAbs(pmrm.getMargin(aliceAcc, true), results.initialMarginHand, 1e8, "Initial Margin Hand");
    assertApproxEqAbs(pmrm.getMargin(aliceAcc, false), results.maintenanceMarginHand, 1e8, "Maintenance Margin Hand");
  }
}
