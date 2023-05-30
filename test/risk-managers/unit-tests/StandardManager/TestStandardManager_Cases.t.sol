pragma solidity ^0.8.13;

import "./TestStandardManagerBase.t.sol";

import "src/feeds/OptionPricing.sol";

import "test/shared/utils/JsonMechIO.sol";

/**
 * Focusing on the margin rules for options
 */
contract UNIT_TestStandardManager_TestCases is TestStandardManagerBase {
  using stdJson for string;

  JsonMechIO immutable jsonParser;

  OptionPricing immutable pricing;

  constructor() {
    jsonParser = new JsonMechIO();
    pricing = new OptionPricing();
  }

  function setUp() public override {
    super.setUp();

    manager.setPricingModule(ethMarketId, pricing);
    manager.setPricingModule(btcMarketId, pricing);
  }

  function testCase1() public {
    string memory json = jsonParser.jsonFromRelPath("/test/risk-managers/unit-tests/StandardManager/test-cases.json");

    ISubAccounts.AssetBalance[] memory balances = _setUpScenario(json, ".Test1");

    (int im, int mm, int mtm) = manager.getMarginByBalances(balances, 1);

    _checkResult(json, ".Test1", im, mm, mtm, 0.001e18); // 0.1% diff
  }

  function _setUpScenario(string memory json, string memory testId)
    internal
    returns (ISubAccounts.AssetBalance[] memory)
  {
    // get spot and perp confidence
    // todo: use 1e18 based number!
    uint[][] memory confs = readUintArray2D(json, string.concat(testId, ".Scenario.SpotPerpConfidences"));

    // set spot feed
    {
      uint ethSpotPrice = json.readUint(string.concat(testId, ".Scenario.ETHSpotPrice"));
      uint btcSpotPrice = json.readUint(string.concat(testId, ".Scenario.BTCSpotPrice"));

      ethFeed.setSpot(ethSpotPrice, confs[0][0] * 1e18);
      btcFeed.setSpot(btcSpotPrice, confs[1][0] * 1e18);
    }

    // set forwards: assume they are all eth
    {
      uint[] memory feedExpiries = json.readUintArray(string.concat(testId, ".Scenario.FeedExpiries"));
      uint[] memory forwardPrices = json.readUintArray(string.concat(testId, ".Scenario.Forwards"));
      uint[] memory forwardConfs = json.readUintArray(string.concat(testId, ".Scenario.ForwardConfidences"));
      // todo: add discounts
      uint[] memory discounts = json.readUintArray(string.concat(testId, ".Scenario.Discounts"));
      uint[] memory discountConfs = json.readUintArray(string.concat(testId, ".Scenario.DiscountConfidences"));

      for (uint i = 0; i < feedExpiries.length; i++) {
        ethFeed.setForwardPrice(block.timestamp + feedExpiries[i], forwardPrices[i], forwardConfs[i]);
        // todo: set discounts?
        // todo: always set eth feed
      }
    }

    {
      // set perp feed
      uint[] memory perpPrices = json.readUintArray(string.concat(testId, ".Scenario.PerpPrice"));
      ethPerpFeed.setSpot(perpPrices[0], confs[0][1] * 1e18);
      btcPerpFeed.setSpot(perpPrices[1], confs[1][1] * 1e18);

      // set stable feed
      uint usdcPrice = json.readUint(string.concat(testId, ".Scenario.USDCValue"));
      stableFeed.setSpot(usdcPrice, 1e18);
    }

    // put options into balances
    // number of assets: cash + eth perp + btc perp + number of options
    string[] memory optionUnderlying = json.readStringArray(string.concat(testId, ".Scenario.OptionUnderlying"));
    uint numAssets = 3 + optionUnderlying.length;

    ISubAccounts.AssetBalance[] memory balances = new ISubAccounts.AssetBalance[](numAssets);

    // put cash and perp assets
    {
      int cashBalance = json.readInt(string.concat(testId, ".Scenario.Cash"));
      int ethPerpBalance = json.readInt(string.concat(testId, ".Scenario.Perps_ETH"));
      int btcPerpBalance = json.readInt(string.concat(testId, ".Scenario.Perps_BTC"));
      balances[0] = ISubAccounts.AssetBalance(cash, 0, cashBalance);
      balances[1] = ISubAccounts.AssetBalance(ethPerp, 0, ethPerpBalance);
      balances[2] = ISubAccounts.AssetBalance(btcPerp, 0, btcPerpBalance);
    }

    // put options assets into balances, also set vol for each strike
    {
      int[] memory optionAmounts = json.readIntArray(string.concat(testId, ".Scenario.OptionAmounts"));
      uint[] memory expiries = json.readUintArray(string.concat(testId, ".Scenario.OptionExpiries"));
      uint[] memory isCalls = json.readUintArray(string.concat(testId, ".Scenario.OptionIsCall"));
      uint[] memory strikes = json.readUintArray(string.concat(testId, ".Scenario.OptionStrikes"));
      uint[] memory vols = json.readUintArray(string.concat(testId, ".Scenario.OptionVols"));
      uint[] memory volConfs = json.readUintArray(string.concat(testId, ".Scenario.OptionVolConfidences"));

      for (uint i; i < optionUnderlying.length; i++) {
        bool isEth = equal(optionUnderlying[i], "ETH");

        // set mocked vol oracle
        MockFeeds feed = isEth ? ethFeed : btcFeed;
        uint64 expiry = uint64(block.timestamp + expiries[i]);
        feed.setVol(expiry, uint128(strikes[i]), uint128(vols[i]), uint64(volConfs[i]));

        IAsset asset = isEth ? ethOption : btcOption;
        uint subId = OptionEncoding.toSubId(expiry, strikes[i], isCalls[i] == 1);

        uint idx = 3 + i;
        balances[idx] = ISubAccounts.AssetBalance(asset, subId, optionAmounts[i]);
      }
    }

    return balances;
  }

  function _checkResult(string memory json, string memory testId, int im, int mm, int mtm, uint deltaPercentage)
    internal
  {
    int expectedIM = json.readInt(string.concat(testId, ".Result.realIM"));
    int expectedMM = json.readInt(string.concat(testId, ".Result.realMM"));
    int expectedMtM = json.readInt(string.concat(testId, ".Result.PortfolioMtM"));

    assertApproxEqRel(expectedIM, im, deltaPercentage);
    assertApproxEqRel(expectedMM, mm, deltaPercentage);
    assertApproxEqRel(expectedMtM, mtm, deltaPercentage);
  }

  // helper
  function readUintArray2D(string memory json, string memory key) internal pure returns (uint[][] memory) {
    return abi.decode(vm.parseJson(json, key), (uint[][]));
  }

  function equal(string memory a, string memory b) internal pure returns (bool) {
    return keccak256(bytes(a)) == keccak256(bytes(b));
  }
}
