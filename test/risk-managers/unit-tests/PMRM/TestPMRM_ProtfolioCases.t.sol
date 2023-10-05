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
    // 930, 928
    // 946, 944
    _runTestCase(".test_long_box_pm");
  }

  function testCase16() public {
    _runTestCase(".test_short_box_pm");
  }

  function testCase17() public {
    // wrong!
    // _runTestCase(".test_long_box_short_box_different_expiries_pm");
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
