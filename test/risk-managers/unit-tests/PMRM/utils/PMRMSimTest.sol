pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "src/risk-managers/PMRM.sol";
import "src/assets/CashAsset.sol";
import "src/SubAccounts.sol";
import "src/interfaces/IManager.sol";
import "src/interfaces/IAsset.sol";
import "src/interfaces/ISubAccounts.sol";

import "test/shared/mocks/MockManager.sol";
import "test/shared/mocks/MockERC20.sol";
import "test/shared/mocks/MockAsset.sol";
import "test/shared/mocks/MockOption.sol";
import "test/shared/mocks/MockSM.sol";
import "test/shared/mocks/MockFeeds.sol";
import "test/auction/mocks/MockCashAsset.sol";

import "test/risk-managers/mocks/MockDutchAuction.sol";
import "test/shared/utils/JsonMechIO.sol";

import "test/risk-managers/unit-tests/PMRM/utils/PMRMTestBase.sol";

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
  }

  struct FeedData {
    uint spotPrice;
    uint spotConfidence;
    uint stablePrice;
    uint stableConfidence;
    uint[] expiries;
    uint[] forwards;
    uint[] forwardConfidences;
    int[] rates;
    uint[] rateConfidences;
  }

  function readOptionData(string memory json, string memory testId) internal pure returns (OptionData[] memory) {
    uint[] memory expiries = json.readUintArray(string.concat(testId, ".OptionExpiries"));
    uint[] memory strikes = json.readUintArray(string.concat(testId, ".OptionStrikes"));
    uint[] memory isCall = json.readUintArray(string.concat(testId, ".OptionIsCall"));
    int[] memory amounts = json.readIntArray(string.concat(testId, ".OptionAmounts"));
    uint[] memory vols = json.readUintArray(string.concat(testId, ".OptionVols"));
    uint[] memory confidences = json.readUintArray(string.concat(testId, ".OptionVolConfidences"));

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
    int cashAmount = json.readInt(string.concat(testId, ".Cash"));
    if (cashAmount != 0) {
      count++;
    }
    int perpAmount = json.readInt(string.concat(testId, ".Perps"));
    if (perpAmount != 0) {
      count++;
    }
    uint baseAmount = json.readUint(string.concat(testId, ".Base"));
    if (baseAmount != 0) {
      count++;
    }

    return OtherAssets({count: count, cashAmount: cashAmount, perpAmount: perpAmount, baseAmount: baseAmount});
  }

  function readFeedData(string memory json, string memory testId) internal pure returns (FeedData memory) {
    uint spotPrice = json.readUint(string.concat(testId, ".SpotPrice"));
    uint spotConfidence = json.readUint(string.concat(testId, ".SpotConfidence"));
    uint stablePrice = json.readUint(string.concat(testId, ".StablePrice"));
    uint stableConfidence = json.readUint(string.concat(testId, ".StableConfidence"));
    uint[] memory expiries = json.readUintArray(string.concat(testId, ".FeedExpiries"));
    uint[] memory forwards = json.readUintArray(string.concat(testId, ".Forwards"));
    uint[] memory forwardConfidences = json.readUintArray(string.concat(testId, ".ForwardConfidences"));
    int[] memory rates = json.readIntArray(string.concat(testId, ".Rates"));
    uint[] memory rateConfidences = json.readUintArray(string.concat(testId, ".RateConfidences"));

    require(expiries.length == forwards.length, "forwards length mismatch");
    require(expiries.length == forwardConfidences.length, "forwardConfidences length mismatch");
    require(expiries.length == rates.length, "rates length mismatch");
    require(expiries.length == rateConfidences.length, "rateConfidences length mismatch");

    return FeedData({
    spotPrice: spotPrice,
    spotConfidence: spotConfidence,
    stablePrice: stablePrice,
    stableConfidence: stableConfidence,
    expiries: expiries,
    forwards: forwards,
    forwardConfidences: forwardConfidences,
    rates: rates,
    rateConfidences: rateConfidences
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

      feed.setVol(
        uint64(expiry), uint128(optionData[i].strike), uint128(optionData[i].vol), uint64(optionData[i].volConfidence)
      );
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

}
