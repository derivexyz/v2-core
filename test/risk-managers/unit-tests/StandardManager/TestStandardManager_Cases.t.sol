// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./TestStandardManagerBase.t.sol";

import "../../../shared/utils/JsonMechIO.sol";
import "lyra-utils/decimals/SignedDecimalMath.sol";

/**
 * Focusing on the margin rules for options
 */
contract UNIT_TestStandardManager_TestCases is TestStandardManagerBase {
  using stdJson for string;
  using SignedDecimalMath for int;

  JsonMechIO immutable jsonParser;

  constructor() {
    jsonParser = new JsonMechIO();
  }

  function setUp() public override {
    super.setUp();

    // override settings
    manager.setOracleContingencyParams(ethMarketId, getDefaultSRMOracleContingency());
    manager.setOracleContingencyParams(btcMarketId, getDefaultSRMOracleContingency());
    manager.setDepegParameters(IStandardManager.DepegParams(0.98e18, 1.2e18));

    // base asset contribute 10% of its value to margin
    manager.setBaseAssetMarginFactor(ethMarketId, 0.1e18, 1e18);
    manager.setBaseAssetMarginFactor(btcMarketId, 0.1e18, 1e18);
  }

  function testCase1() public {
    _runTestCases(".Test1");
  }

  function testCase2() public {
    _runTestCases(".Test2");
  }

  function testCase3() public {
    _runTestCases(".Test3");
  }

  function testCase4() public {
    _runTestCases(".Test4");
  }

  function testCase5() public {
    _runTestCases(".Test5");
  }

  function testCase6() public {
    _runTestCases(".Test6");
  }

  function testCase7() public {
    _runTestCases(".Test7");
  }

  function testCase8() public {
    _runTestCases(".Test8");
  }

  function testCase9() public {
    _runTestCases(".Test9");
  }

  function testCase10() public {
    _runTestCases(".Test10");
  }

  function testCase11() public {
    _runTestCases(".Test11");
  }

  function testCase12() public {
    _runTestCases(".Test12");
  }

  function testCase13() public {
    _runTestCases(".Test13");
  }

  function testCase14() public {
    _runTestCases(".Test14");
  }

  function testCase15() public {
    _runTestCases(".Test15");
  }

  function testCase16() public {
    _runTestCases(".Test16");
  }

  function testCase17() public {
    _runTestCases(".Test17");
  }

  function testCase18() public {
    _runTestCases(".Test18");
  }

  function testCase19() public {
    _runTestCases(".Test19");
  }

  function testCase20() public {
    _runTestCases(".Test20");
  }

  function testCase21() public {
    _runTestCases(".Test21");
  }

  function testCase22() public {
    _runTestCases(".Test22");
  }

  function testCase23() public {
    _runTestCases(".Test23");
  }

  function testCase24() public {
    _runTestCases(".Test24");
  }

  function testCase25() public {
    _runTestCases(".Test25");
  }

  function testCase26() public {
    _runTestCases(".Test26");
  }

  function testCase27() public {
    _runTestCases(".Test27");
  }

  function testCase28() public {
    _runTestCases(".Test28");
  }

  function _runTestCases(string memory testId) internal {
    string memory json = jsonParser.jsonFromRelPath("/test/risk-managers/unit-tests/StandardManager/test-cases.json");
    ISubAccounts.AssetBalance[] memory balances = _setUpScenario(json, testId);
    (int im, int mm, int mtm) = manager.getMarginByBalances(balances, aliceAcc);
    _checkResult(json, testId, im, mm, mtm, 0.001e18); // 0.1% diff
  }

  function _setUpScenario(string memory json, string memory testId)
    internal
    returns (ISubAccounts.AssetBalance[] memory)
  {
    // get spot and perp confidence
    uint[][] memory confs = readUintArray2D(json, string.concat(testId, ".Scenario.SpotPerpConfidences"));

    // set spot feed
    {
      uint ethSpotPrice = json.readUint(string.concat(testId, ".Scenario.ETHSpotPrice"));
      uint btcSpotPrice = json.readUint(string.concat(testId, ".Scenario.BTCSpotPrice"));

      ethFeed.setSpot(ethSpotPrice, confs[0][0]);
      btcFeed.setSpot(btcSpotPrice, confs[1][0]);

      // set perp feed
      uint[] memory perpPrices = json.readUintArray(string.concat(testId, ".Scenario.PerpPrice"));
      ethPerp.setMockPerpPrice(perpPrices[0], confs[0][1]);
      btcPerp.setMockPerpPrice(perpPrices[1], confs[1][1]);

      // set stable feed
      uint usdcPrice = json.readUint(string.concat(testId, ".Scenario.USDCValue"));
      stableFeed.setSpot(usdcPrice, 1e18);
    }

    string[] memory optionUnderlying = json.readStringArray(string.concat(testId, ".Scenario.OptionUnderlying"));

    // set forwards: assume they are all eth
    {
      uint[] memory feedExpiries = json.readUintArray(string.concat(testId, ".Scenario.FeedExpiries"));
      uint[] memory forwardPrices = json.readUintArray(string.concat(testId, ".Scenario.Forwards"));
      uint[] memory forwardConfs = json.readUintArray(string.concat(testId, ".Scenario.ForwardConfidences"));

      for (uint i = 0; i < feedExpiries.length; i++) {
        bool isEth = equal(optionUnderlying[i], "ETH");

        // close to expiring: we will set the "settlement price" to the forward price feed
        if (feedExpiries[i] < 3600) {
          if (isEth) {
            uint price = json.readUint(string.concat(testId, ".Scenario.SettlementPriceETH"));
            ethFeed.setForwardPrice(block.timestamp + feedExpiries[i], price, forwardConfs[i]);
          } else {
            uint price = json.readUint(string.concat(testId, ".Scenario.SettlementPriceBTC"));

            btcFeed.setForwardPrice(block.timestamp + feedExpiries[i], price, forwardConfs[i]);
          }
        } else {
          if (isEth) {
            ethFeed.setForwardPrice(block.timestamp + feedExpiries[i], forwardPrices[i], forwardConfs[i]);
          } else {
            btcFeed.setForwardPrice(block.timestamp + feedExpiries[i], forwardPrices[i], forwardConfs[i]);
          }
        }
      }
    }

    // put options into balances
    // number of assets: cash + eth perp + btc perp + number of options
    // string[] memory optionUnderlying = json.readStringArray(string.concat(testId, ".Scenario.OptionUnderlying"));
    uint numAssets = 5 + optionUnderlying.length;

    ISubAccounts.AssetBalance[] memory balances = new ISubAccounts.AssetBalance[](numAssets);

    // put cash and perp assets
    {
      int cashBalance = json.readInt(string.concat(testId, ".Scenario.Cash"));
      int ethPerpBalance = json.readInt(string.concat(testId, ".Scenario.Perps_ETH"));
      int btcPerpBalance = json.readInt(string.concat(testId, ".Scenario.Perps_BTC"));
      balances[0] = ISubAccounts.AssetBalance(cash, 0, cashBalance);
      balances[1] = ISubAccounts.AssetBalance(ethPerp, 0, ethPerpBalance);
      balances[2] = ISubAccounts.AssetBalance(btcPerp, 0, btcPerpBalance);

      {
        int ethBalance = json.readInt(string.concat(testId, ".Scenario.wETH"));
        balances[3] = ISubAccounts.AssetBalance(wethAsset, 0, ethBalance);

        int btcBalance = json.readInt(string.concat(testId, ".Scenario.wBTC"));
        balances[4] = ISubAccounts.AssetBalance(wbtcAsset, 0, btcBalance);
      }

      // set mocked pnl
      {
        int ethEntryPrice = json.readInt(string.concat(testId, ".Scenario.LastEntryETH"));
        (uint perpPrice,) = ethPerp.getPerpPrice();
        int pnl = (int(perpPrice) - ethEntryPrice).multiplyDecimal(ethPerpBalance);
        int funding = _getPerpFunding(json, testId, ethPerpBalance, true);
        ethPerp.mockAccountPnlAndFunding(aliceAcc, pnl, funding);
      }

      {
        int btcEntryPrice = json.readInt(string.concat(testId, ".Scenario.LastEntryBTC"));
        (uint perpPrice,) = btcPerp.getPerpPrice();
        int pnl = (int(perpPrice) - btcEntryPrice).multiplyDecimal(btcPerpBalance);
        int funding = _getPerpFunding(json, testId, btcPerpBalance, false);
        btcPerp.mockAccountPnlAndFunding(aliceAcc, pnl, funding);
      }
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
        uint128 strike = uint128(strikes[i]) / 1e10 * 1e10; // removing dust

        feed.setVol(expiry, strike, vols[i], volConfs[i]);

        IAsset asset = isEth ? ethOption : btcOption;
        uint subId = OptionEncoding.toSubId(expiry, strike, isCalls[i] == 1);

        uint idx = 5 + i;
        balances[idx] = ISubAccounts.AssetBalance(asset, subId, optionAmounts[i]);
      }
    }

    // mock perp scenario
    {}

    return balances;
  }

  function _getPerpFunding(string memory json, string memory testId, int position, bool isETH)
    internal
    view
    returns (int)
  {
    int globalFundingIdx;
    int accFundingIdx;
    uint indexPrice;
    if (isETH) {
      globalFundingIdx = json.readInt(string.concat(testId, ".Scenario.ETHGlobalFundingIndex"));
      accFundingIdx = json.readInt(string.concat(testId, ".Scenario.AccountETHFundingIndex"));
      (indexPrice,) = ethFeed.getSpot();
    } else {
      globalFundingIdx = json.readInt(string.concat(testId, ".Scenario.BTCGlobalFundingIndex"));
      accFundingIdx = json.readInt(string.concat(testId, ".Scenario.AccountBTCFundingIndex"));
      (indexPrice,) = btcFeed.getSpot();
    }
    int rate = globalFundingIdx - accFundingIdx;

    return -position.multiplyDecimal(rate);
  }

  function _checkResult(string memory json, string memory testId, int im, int mm, int mtm, uint deltaPercentage)
    internal
  {
    int expectedIM = json.readInt(string.concat(testId, ".Result.realIM"));
    int expectedMM = json.readInt(string.concat(testId, ".Result.realMM"));
    int expectedMtM = json.readInt(string.concat(testId, ".Result.PortfolioMtM"));

    assertApproxEqRel(im, expectedIM, deltaPercentage, "IM assertion failed");
    assertApproxEqRel(mm, expectedMM, deltaPercentage, "MM assertion failed");

    // mtm should have higher tolerance cuz we only assume mtm gas no discount from standard manager
    assertApproxEqRel(mtm, expectedMtM, deltaPercentage, "MtM assertion failed");
  }

  // helper
  function readUintArray2D(string memory json, string memory key) internal pure returns (uint[][] memory) {
    return abi.decode(vm.parseJson(json, key), (uint[][]));
  }

  function equal(string memory a, string memory b) internal pure returns (bool) {
    return keccak256(bytes(a)) == keccak256(bytes(b));
  }
}
