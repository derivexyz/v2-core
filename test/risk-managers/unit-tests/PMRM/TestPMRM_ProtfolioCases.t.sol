pragma solidity ^0.8.18;

import "lyra-utils/decimals/SignedDecimalMath.sol";
import "../../../../src/risk-managers/PMRM.sol";
import "../../../../src/interfaces/ISubAccounts.sol";
import "../../../shared/mocks/MockFeeds.sol";

import "../../../shared/mocks/MockFeeds.sol";

import "./utils/PMRMTestBase.sol";

import "../TestCaseExpiries.t.sol";

import "forge-std/console2.sol";

contract UNIT_TestPMRM_PortfolioCases is TestCaseExpiries, PMRMTestBase {
  using SignedDecimalMath for int;
  using stdJson for string;

  uint originalTime;

  uint mockAccIdToRequest = 0;

  function setUp() public override {
    originalTime = block.timestamp;

    super.setUp();

    // setup default expires
    _setDefaultSpotAndForwardForETH();

    // setup default rate feed for all expires
    _setRateFeedForETH();

    _setupPerpPrices();

    IPMRMLib.MarginParameters memory marginParams = IPMRMLib.MarginParameters({
      imFactor: 1.3e18,
      baseStaticDiscount: 0.95e18,
      rateMultScale: 4e18,
      rateAddScale: 0.12e18 // override this param
    });
    lib.setMarginParams(marginParams);

    IPMRMLib.OtherContingencyParameters memory otherContParams = IPMRMLib.OtherContingencyParameters({
      pegLossThreshold: 0.98e18,
      pegLossFactor: 2e18,
      confThreshold: 0.6e18,
      confMargin: 0.4e18,
      basePercent: 0.025e18, // override this param
      perpPercent: 0.025e18, // override this param
      optionPercent: 0.01e18
    });
    lib.setOtherContingencyParams(otherContParams);

    // set back timestamp
    vm.warp(originalTime);
  }

  function _setupPerpPrices() public {
    mockPerp.setMockPerpPrice(ethDefaultPrice + 1e18, 1e18); // $1 diff
  }

  /// @dev not used
  function _btcFeeds() internal view override returns (MockFeeds) {
    return feed;
  }

  function _ethFeeds() internal view override returns (MockFeeds) {
    return feed;
  }

  function testCase1() public {
    _runTestCase(".test_short_ITM_call_pm");
  }

  function testCase2() public {
    _runTestCase(".test_short_ITM_put_pm");
  }

  function testCase3() public {
    _runTestCase(".test_long_ATM_put_pm");
  }

  function testCase4() public {
    _runTestCase(".test_long_ATM_call_pm");
  }

  function testCase5() public {
    _runTestCase(".test_short_OTM_call_pm");
  }

  function testCase6() public {
    _runTestCase(".test_short_OTM_pm");
  }

  function testCase7() public {
    _runTestCase(".test_long_ITM_call_spread_pm");
  }

  function testCase8() public {
    _runTestCase(".test_long_OTM_call_spread_pm");
  }

  function testCase9() public {
    _runTestCase(".test_short_ITM_call_spread_pm");
  }

  function testCase10() public {
    _runTestCase(".test_short_OTM_call_spread_pm");
  }

  function testCase11() public {
    _runTestCase(".test_long_ITM_put_spread_pm");
  }

  function testCase12() public {
    _runTestCase(".test_long_OTM_put_spread_pm");
  }

  function testCase13() public {
    _runTestCase(".test_short_ATM_put_spread_pm");
  }

  function testCase14() public {
    _runTestCase(".test_short_OTM_put_spread_pm");
  }

  function testCase15() public {
    _runTestCase(".test_long_box_pm");
  }

  function testCase16() public {
    _runTestCase(".test_short_box_pm");
  }

  function testCase17() public {
    _runTestCase(".test_long_box_short_box_different_expiries_pm");
  }

  function testCase18() public {
    _runTestCase(".test_long_ATM_perp_pm");
  }

  function testCase19() public {
    _runTestCase(".test_long_ITM_perp_pm");
  }

  // do the same for test_long_ITM_perp_pm test_long_OTM_perp_pm test_short_ATM_perp_pm test_short_ITM_perp_pm test_short_OTM_perp_pm
  function testCase20() public {
    _runTestCase(".test_long_OTM_perp_pm");
  }

  function testCase21() public {
    _runTestCase(".test_short_ATM_perp_pm");
  }

  function testCase22() public {
    _runTestCase(".test_short_ITM_perp_pm");
  }

  function testCase23() public {
    _runTestCase(".test_short_OTM_perp_pm");
  }

  function testCase24() public {
    _runTestCase(".test_long_base_pm");
  }

  function testCase25() public {
    _runTestCase(".test_covered_atm_call_pm");
  }

  function testCase26() public {
    _runTestCase(".test_covered_itm_call_pm");
  }

  function testCase27() public {
    _runTestCase(".test_delta_hedged_perp_pm");
  }

  function testCase28() public {
    _runTestCase(".test_long_forward_pm");
  }

  function testCase29() public {
    _runTestCase(".test_short_forward_pm");
  }

  function testCase30() public {
    _runTestCase(".test_long_ITM_forward_pm");
  }

  function testCase31() public {
    _runTestCase(".test_short_ITM_forward_pm");
  }

  function testCase32() public {
    _runTestCase(".test_long_OTM_forward_pm");
  }

  function testCase33() public {
    _runTestCase(".test_short_OTM_forward_pm");
  }

  function testCase34() public {
    _runTestCase(".test_long_perp_short_call_pm");
  }

  function testCase35() public {
    _runTestCase(".test_short_perp_long_call_pm");
  }

  function testCase36() public {
    _runTestCase(".test_multi_expiry_pm");
  }

  function testCase37() public {
    _runTestCase(".test_long_jelly_roll_pm");
  }

  function testCase38() public {
    _runTestCase(".test_short_jelly_roll_pm");
  }

  /**
   * Tests with some env settings
   */

  function testCase39() public {
    stableFeed.setSpot(0.2e18, 1e18);
    _runTestCase(".test_depeg_contingency_pm");
  }

  // function testCase40() public {
  //   uint64 expiry = uint64(dateToExpiry["20230118"]);
  //   feed.setSpot(ethDefaultPrice, 0.1e18);
  //   feed.setVol(expiry, 1700e18, 0.5e18, 0.3e18);
  //   feed.setForwardPrice(expiry, ethDefaultPrice + 4.75e18, 0.4e18);
  //   _runTestCase(".test_oracle_cont_long_call_pm");
  // }

  // function testCase41() public {
  //   uint64 expiry = uint64(dateToExpiry["20230118"]);
  //   feed.setSpot(ethDefaultPrice, 0.1e18);
  //   feed.setVol(expiry, 1700e18, 0.5e18, 0.1e18);
  //   feed.setForwardPrice(expiry, ethDefaultPrice + 4.75e18, 0.4e18);
  //   _runTestCase(".test_oracle_cont_short_call_pm");
  // }

  // function testCase42() public {
  // uint64 expiry = uint64(dateToExpiry["20230118"]);
  // feed.setSpot(ethDefaultPrice, 0.1e18);
  // feed.setVol(expiry, 1700e18, 0.01e18, 0.1e18);
  // feed.setForwardPrice(expiry, ethDefaultPrice + 4.75e18, 0.02e18);

  //   _runTestCase(".test_oracle_cont_base_asset_pm");
  // }

  // function testCase43() public {
  //   uint64 expiry = uint64(dateToExpiry["20230118"]);
  //   feed.setSpot(ethDefaultPrice, 0.3e18);
  //   feed.setVol(expiry, 1700e18, 0.5e18, 0.1e18);
  //   feed.setForwardPrice(expiry, ethDefaultPrice + 4.75e18, 0.02e18);
  //   _runTestCase(".test_oracle_cont_long_perp_asset_pm");
  // }

  function testCase44() public {
    uint64 expiry = uint64(dateToExpiry["20230118"]);
    feed.setSpot(2004e18, 0.3e18);

    feed.setVol(expiry, 1700e18, 0.15e18, 0.1e18);
    feed.setVol(expiry, 2100e18, 1.01e18, 0.1e18);
    feed.setVol(expiry, 1000e18, 0.33e18, 0.1e18);

    feed.setForwardPrice(uint64(dateToExpiry["20230227"]), 2014.7545e18, 0.2e18);

    // set perp price
    mockPerp.setMockPerpPrice(2017e18, 0.3e18);
    // perpFeed.setSpotDiff(17e18, 0.3e18);

    _runTestCase(".test_general_portfolio_pm");
  }

  function _runTestCase(string memory name) internal {
    (ISubAccounts.AssetBalance[] memory balances, int _mmInteger, int _imInteger) = _loadTestData(name);
    int im = pmrm.getMarginByBalances(balances, true);
    int mm = pmrm.getMarginByBalances(balances, false);

    assertEq(mm / 1e18, _mmInteger, string.concat("MM not match for case: ", name));
    assertEq(im / 1e18, _imInteger, string.concat("IM not match for case: ", name));
  }

  function _loadTestData(string memory name) internal returns (ISubAccounts.AssetBalance[] memory, int mm, int im) {
    string memory json = jsonParser.jsonFromRelPath("/test/risk-managers/unit-tests/PMRM/test-cases-portfolio-pm.json");
    bytes memory testCaseDetail = json.parseRaw(name);
    TestCase memory testCase = abi.decode(testCaseDetail, (TestCase));

    uint totalAssets = testCase.options.length + testCase.perps.length + testCase.bases.length + 1;

    ISubAccounts.AssetBalance[] memory balances = new ISubAccounts.AssetBalance[](totalAssets);

    // put in options
    for (uint i = 0; i < testCase.options.length; i++) {
      Option memory optionDetail = testCase.options[i];

      uint128 strike = uint128(optionDetail.strike * 1e18);
      uint64 expiry = uint64(dateToExpiry[optionDetail.expiry]);

      if (expiry == 0) revert(string.concat("Unset date to expiry value: ", optionDetail.expiry));

      // set vol and its confidence for this expiry + strike
      (uint oldVol,) = feed.getVol(strike, expiry);
      if (oldVol == 0) feed.setVol(expiry, strike, 0.5e18, 1e18);

      // fill in balance
      balances[i] = ISubAccounts.AssetBalance(
        option, OptionEncoding.toSubId(expiry, strike, equal(optionDetail.typeOption, "call")), optionDetail.amount
      );
    }

    // put in perps
    for (uint i = 0; i < testCase.perps.length; i++) {
      uint offset = testCase.options.length;
      Perp memory perp = testCase.perps[i];
      balances[i + offset] = ISubAccounts.AssetBalance(mockPerp, 0, perp.amount);

      (uint perpPrice,) = mockPerp.getPerpPrice();
      int pnl = (int(perpPrice) - perp.entryPrice).multiplyDecimal(perp.amount);
      mockPerp.mockAccountPnlAndFunding(mockAccIdToRequest, pnl, 0);
    }

    // put in bases
    for (uint i = 0; i < testCase.bases.length; i++) {
      uint offset = testCase.options.length + testCase.perps.length;
      Base memory base = testCase.bases[i];
      balances[i + offset] = ISubAccounts.AssetBalance(baseAsset, 0, base.amount);
    }

    // put in cash at the end
    balances[totalAssets - 1] = ISubAccounts.AssetBalance(cash, 0, testCase.cash);

    mm = testCase.result.mm;
    im = testCase.result.im;

    return (balances, mm, im);
  }
}
