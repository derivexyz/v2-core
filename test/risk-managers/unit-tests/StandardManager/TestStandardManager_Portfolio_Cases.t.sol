// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./TestStandardManagerBase.t.sol";

import "lyra-utils/decimals/SignedDecimalMath.sol";
import "../../../../scripts/config-local.sol";
import "../TestCaseExpiries.t.sol";

/**
 * Focusing on the margin rules for options
 */
contract UNIT_TestStandardManager_Portfolio_Cases is TestCaseExpiries, TestStandardManagerBase {
  using stdJson for string;
  using SignedDecimalMath for int;

  uint constant mockAccIdToRequest = 1;

  function setUp() public override {
    super.setUp();

    manager.setOracleContingencyParams(ethMarketId, getDefaultSRMOracleContingency());
    manager.setOracleContingencyParams(btcMarketId, getDefaultSRMOracleContingency());

    // base asset contribute 80% of its value to margin
    manager.setBaseAssetMarginFactor(ethMarketId, 0.8e18);
    manager.setBaseAssetMarginFactor(btcMarketId, 0.8e18);

    manager.setDepegParameters(IStandardManager.DepegParams(0.98e18, 1.2e18));

    _setDefaultSpotAndForwardForETH();

    _setDefaultSpotAndForwardForBTC();

    _setUpAdditional();
  }

  /// @dev override to set up the environment
  function _ethFeeds() internal view override returns (MockFeeds feed) {
    return ethFeed;
  }

  /// @dev override to setup the environment
  function _btcFeeds() internal view override returns (MockFeeds feed) {
    return btcFeed;
  }

  function _setUpAdditional() internal {
    ethPerp.setMockPerpPrice(ethDefaultPrice + 1e18, 1e18); // $1 diff
    btcPerp.setMockPerpPrice(btcDefaultPrice + 20e18, 1e18); // $20 diff
  }

  function testCase1() public {
    _runTestCase(".test_long_ATM_call");
  }

  function testCase2() public {
    _runTestCase(".test_long_ATM_put");
  }

  function testCase3() public {
    _runTestCase(".test_short_ITM_call");
  }

  function testCase4() public {
    _runTestCase(".test_short_ITM_put");
  }

  function testCase5() public {
    _runTestCase(".test_short_OTM_call");
  }

  function testCase6() public {
    _runTestCase(".test_short_OTM_put");
  }

  function testCase7() public {
    _runTestCase(".test_short_call_spread_with_MaxLoss");
  }

  function testCase8() public {
    _runTestCase(".test_short_put_spread_with_MaxLoss");
  }

  function testCase9() public {
    _runTestCase(".test_short_call_spread_with_iso_margin");
  }

  function testCase10() public {
    _runTestCase(".test_short_put_spread_with_iso_margin");
  }

  function testCase11() public {
    _runTestCase(".test_short_spread_over_two_expiries_both_MaxLoss");
  }

  function testCase12() public {
    _runTestCase(".test_short_spread_two_expiries_both_iso");
  }

  function testCase13() public {
    _runTestCase(".test_short_spread_two_currencies_one_iso_one_MaxLoss");
  }

  function testCase14() public {
    _runTestCase(".test_two_currencies_two_expiries_each_iso_and_MaxLoss_for_each");
  }

  function testCase15() public {
    _runTestCase(".test_long_call_spread");
  }

  function testCase16() public {
    _runTestCase(".test_long_put_spread");
  }

  function testCase17() public {
    _runTestCase(".test_long_box");
  }

  function testCase18() public {
    _runTestCase(".test_short_box");
  }

  function testCase19() public {
    _runTestCase(".test_short_put_with_0_strike_MaxLoss");
  }

  function testCase20() public {
    stableFeed.setSpot(0.1e18, 1e18);

    _runTestCase(".test_USDC_depeg");
  }

  function testCase21() public {
    _runTestCase(".test_short_call_spread_with_offset");
  }

  function testCase22() public {
    _runTestCase(".test_short_eth_call_with_btc_collateral");
  }

  function testCase23() public {
    _runTestCase(".test_short_btc_spread_with_eth_collateral");
  }

  function testCase24() public {
    _runTestCase(".test_borrowing_ETH");
  }

  function testCase25() public {
    _runTestCase(".test_short_eth_call_with_USDC_and_BTC");
  }

  function testCase26() public {
    _runTestCase(".test_long_ATM_perp");
  }

  function testCase27() public {
    _runTestCase(".test_long_OTM_perp");
  }

  function testCase28() public {
    _runTestCase(".test_long_ITM_perp");
  }

  function testCase29() public {
    _runTestCase(".test_short_ATM_perp");
  }

  function testCase30() public {
    _runTestCase(".test_short_OTM_perp");
  }

  function testCase31() public {
    _runTestCase(".test_short_ITM_perp");
  }

  function testCase32() public {
    _runTestCase(".test_long_perp_with_btc");
  }

  function testCase33() public {
    // 2023-1-18, 2000 Call: {"vol": 0.5, "confidence": 0.1}
    ethFeed.setVol(uint64(dateToExpiry["20230118"]), 2000e18, 0.5e18, 0.1e18);
    _runTestCase(".test_short_call_low_vol_conf");
  }

  function testCase34() public {
    uint64 expiry = uint64(dateToExpiry["20230118"]);
    // 2023-1-18, 2000 Call: {"vol": 0.5, "confidence": 0.5}
    ethFeed.setVol(expiry, 2000e18, 0.5e18, 0.5e18);
    // forward conf < 0.4, right under the edge
    ethFeed.setForwardPrice(expiry, ethDefaultPrice + 4.75e18, 0.4e18 - 1);

    _runTestCase(".test_short_call_low_vol_and_fwd_confidence");
  }

  function testCase35() public {
    // same as previous
    uint64 expiry = uint64(dateToExpiry["20230118"]);
    ethFeed.setVol(expiry, 2000e18, 0.5e18, 0.5e18);
    ethFeed.setForwardPrice(expiry, ethDefaultPrice + 4.75e18, 0.4e18);
    // also spot conf = 0.2
    ethFeed.setSpot(ethDefaultPrice, 0.2e18);

    _runTestCase(".test_short_call_low_spot_vol_fwd_confidence");
  }

  function testCase36() public {
    uint64 expiry = uint64(dateToExpiry["20230118"]);
    // same as previous
    ethFeed.setVol(expiry, 2000e18, 0.5e18, 0.5e18);
    ethFeed.setForwardPrice(expiry, ethDefaultPrice + 4.75e18, 0.4e18);
    ethFeed.setSpot(ethDefaultPrice, 0.2e18);

    _runTestCase(".test_long_call_low_spot_vol_fwd_confidence");
  }

  function testCase37() public {
    uint64 expiry = uint64(dateToExpiry["20230118"]);
    ethFeed.setVol(expiry, 2000e18, 0.5e18, 0.3e18); // 0.3 conf
    ethFeed.setForwardPrice(expiry, ethDefaultPrice + 4.75e18, 0.4e18);
    ethFeed.setSpot(ethDefaultPrice, 0.9e18); // 0.9

    _runTestCase(".test_short_options_two_expiries_low_conf_one_expiry");
  }

  function testCase38() public {
    ethPerp.setMockPerpPrice(ethDefaultPrice + 1e18, 0.1e18); // $1 diff

    _runTestCase(".test_long_eth_perp_low_perp_confidence");
  }

  function testCase39() public {
    ethFeed.setSpot(ethDefaultPrice, 0.1e18); // 0.1 conf

    _runTestCase(".test_base_asset_low_spot_confidence");
  }

  function testCase40() public {
    _runTestCase(".test_ITM_put_with_IM_multiple_of_MM");
  }

  function testCase41() public {
    stableFeed.setSpot(0.1e18, 1e18);
    _runTestCase(".test_long_perp_and_USDC_depeg");
  }

  function testCase42() public {
    uint64 expiry = uint64(dateToExpiry["20230118"]);
    stableFeed.setSpot(0.97e18, 1e18);

    ethFeed.setVol(expiry, 2000e18, 0.5e18, 0.5e18); // 0.5 conf
    ethFeed.setForwardPrice(expiry, ethDefaultPrice + 4.75e18, 0.4e18 - 1);
    ethFeed.setSpot(ethDefaultPrice, 0.2e18); // 0.2 conf

    _runTestCase(".test_general_portfolio");
  }

  function _runTestCase(string memory name) internal {
    (ISubAccounts.AssetBalance[] memory balances, int _mmInteger, int _imInteger) = _loadTestData(name);
    (int im, int mm,) = manager.getMarginByBalances(balances, mockAccIdToRequest);

    assertEq(mm / 1e18, _mmInteger, string.concat("MM not match for case: ", name));
    assertEq(im / 1e18, _imInteger, string.concat("IM not match for case: ", name));
  }

  function _loadTestData(string memory name) internal returns (ISubAccounts.AssetBalance[] memory, int mm, int im) {
    string memory json =
      jsonParser.jsonFromRelPath("/test/risk-managers/unit-tests/StandardManager/test-cases-portfolio.json");
    bytes memory testCaseDetail = json.parseRaw(name);
    TestCase memory testCase = abi.decode(testCaseDetail, (TestCase));

    uint totalAssets = testCase.options.length + testCase.perps.length + testCase.bases.length + 1;

    ISubAccounts.AssetBalance[] memory balances = new ISubAccounts.AssetBalance[](totalAssets);

    // put in options
    for (uint i = 0; i < testCase.options.length; i++) {
      Option memory option = testCase.options[i];

      uint128 strike = uint128(option.strike * 1e18);
      uint64 expiry = uint64(dateToExpiry[option.expiry]);

      if (expiry == 0) revert(string.concat("Unset date to expiry value: ", option.expiry));

      // set vol and its confidence for this expiry + strike
      if (equal(option.underlying, "eth")) {
        (uint oldVol,) = ethFeed.getVol(strike, expiry);
        if (oldVol == 0) ethFeed.setVol(expiry, strike, 0.5e18, 1e18);
      } else {
        (uint oldVol,) = btcFeed.getVol(strike, expiry);
        if (oldVol == 0) btcFeed.setVol(expiry, strike, 0.5e18, 1e18);
      }

      // fill in balance
      balances[i] = ISubAccounts.AssetBalance(
        equal(option.underlying, "eth") ? ethOption : btcOption,
        OptionEncoding.toSubId(expiry, strike, equal(option.typeOption, "call")),
        option.amount * 1e10
      );
    }

    // put in perps
    for (uint i = 0; i < testCase.perps.length; i++) {
      uint offset = testCase.options.length;
      Perp memory perp = testCase.perps[i];

      if (equal(perp.underlying, "eth")) {
        balances[i + offset] = ISubAccounts.AssetBalance(ethPerp, 0, perp.amount * 1e10);

        (uint perpPrice,) = ethPerp.getPerpPrice();
        int pnl = (int(perpPrice) - (perp.entryPrice * 1e10)).multiplyDecimal(perp.amount * 1e10);
        ethPerp.mockAccountPnlAndFunding(mockAccIdToRequest, pnl, 0);
      } else {
        balances[i + offset] = ISubAccounts.AssetBalance(btcPerp, 0, perp.amount * 1e10);

        (uint perpPrice,) = btcPerp.getPerpPrice();
        int pnl = (int(perpPrice) - (perp.entryPrice * 1e10)).multiplyDecimal(perp.amount * 1e10);
        btcPerp.mockAccountPnlAndFunding(mockAccIdToRequest, pnl, 0);
      }
    }

    // put in bases
    for (uint i = 0; i < testCase.bases.length; i++) {
      uint offset = testCase.options.length + testCase.perps.length;
      Base memory base = testCase.bases[i];

      if (equal(base.underlying, "eth")) {
        balances[i + offset] = ISubAccounts.AssetBalance(wethAsset, 0, base.amount * 1e10);
      } else {
        balances[i + offset] = ISubAccounts.AssetBalance(wbtcAsset, 0, base.amount * 1e10);
      }
    }

    // put in cash at the end
    balances[totalAssets - 1] = ISubAccounts.AssetBalance(cash, 0, testCase.cash * 1e10);

    mm = testCase.result.mm;
    im = testCase.result.im;

    return (balances, mm, im);
  }
}
