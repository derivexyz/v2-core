pragma solidity ^0.8.13;

import "./TestStandardManagerBase.t.sol";

import "../../../../src/feeds/OptionPricing.sol";

import "../../../shared/utils/JsonMechIO.sol";
import "lyra-utils/decimals/SignedDecimalMath.sol";
import "../../../../scripts/config.sol";

/**
 * Focusing on the margin rules for options
 */
contract UNIT_TestStandardManager_TestCases2 is TestStandardManagerBase {
  using stdJson for string;
  using SignedDecimalMath for int;

  JsonMechIO immutable jsonParser;

  OptionPricing immutable pricing;

  uint[8] expiries;

  mapping(string => uint) dateToExpiry;

  uint constant ethDefaultPrice = 2000e18;
  uint constant btcDefaultPrice = 28000e18;

  
  /// @notice the order is according to the alphabet order of JSON file 
  struct Option {
    int amount;
    string expiry;
    uint strike;
    string typeOption;
    string underlying;
  }

  struct Result {
    int im;
    int mm;
  }

  struct TestCase {
    Option[] options;
    Option[] perps;
    Result result;
  }

  constructor() {
    jsonParser = new JsonMechIO();
    pricing = new OptionPricing();

    expiries[0] = block.timestamp + 3 days + 8 hours;  //  2023 / 1 / 4
    expiries[1] = block.timestamp + 10 days + 8 hours; //  2023 / 1 / 11
    expiries[2] = block.timestamp + 17 days + 8 hours; //  2023 / 1 / 18
    expiries[3] = block.timestamp + 57 days + 8 hours; //  2023 / 2 / 27
    expiries[4] = block.timestamp + 215 days + 8 hours; // 2023 / 8 / 4
    expiries[5] = block.timestamp + 222 days + 8 hours; // 2023 / 8 / 11
    expiries[6] = block.timestamp + 229 days + 8 hours; // 2023 / 8 / 18
    expiries[7] = block.timestamp + 238 days + 8 hours; // 2023 / 8 / 25

    dateToExpiry["20230104"] = expiries[0];
    dateToExpiry["20230111"] = expiries[1];
    dateToExpiry["20230118"] = expiries[2];
    dateToExpiry["20230227"] = expiries[3];
    dateToExpiry["20230804"] = expiries[4];
    dateToExpiry["20230811"] = expiries[5];
    dateToExpiry["20230818"] = expiries[6];
    dateToExpiry["20230825"] = expiries[7];
  }

  function setUp() public override {
    super.setUp();

    manager.setPricingModule(ethMarketId, pricing);
    manager.setPricingModule(btcMarketId, pricing);

    // override settings
    IStandardManager.OptionMarginParams memory params = getDefaultSRMOptionParam();

    manager.setOptionMarginParams(ethMarketId, params);
    manager.setOptionMarginParams(btcMarketId, params);

    manager.setOracleContingencyParams(
      ethMarketId, IStandardManager.OracleContingencyParams(0.4e18, 0.4e18, 0.4e18, 0.4e18)
    );
    manager.setOracleContingencyParams(
      btcMarketId, IStandardManager.OracleContingencyParams(0.4e18, 0.4e18, 0.4e18, 0.4e18)
    );
    manager.setDepegParameters(IStandardManager.DepegParams(0.98e18, 1.2e18));

    // maintenance margin is 5% of perp price, maintenance margin = 1.3x
    manager.setPerpMarginRequirements(ethMarketId, 0.05e18, 0.065e18);
    manager.setPerpMarginRequirements(btcMarketId, 0.05e18, 0.065e18);

    // base asset contribute 10% of its value to margin
    manager.setBaseMarginDiscountFactor(ethMarketId, 0.1e18);
    manager.setBaseMarginDiscountFactor(btcMarketId, 0.1e18);

    _setDefaultEnv();
  }

  function _setDefaultEnv() internal {
    uint conf = 1e18;

    ethFeed.setSpot(ethDefaultPrice, conf);
    btcFeed.setSpot(btcDefaultPrice, conf);

    ethPerp.setMockPerpPrice(ethDefaultPrice + 1e18, conf); // $1 diff
    btcPerp.setMockPerpPrice(btcDefaultPrice + 20e18, conf); // $20 diff
    
    ethFeed.setForwardPrice(expiries[0], ethDefaultPrice + 0.91e18, conf);
    ethFeed.setForwardPrice(expiries[1], ethDefaultPrice + 2.83e18, conf);
    ethFeed.setForwardPrice(expiries[2], ethDefaultPrice + 4.75e18, conf);
    ethFeed.setForwardPrice(expiries[3], ethDefaultPrice + 15.76e18, conf);
    ethFeed.setForwardPrice(expiries[4], ethDefaultPrice + 59e18, conf);
    ethFeed.setForwardPrice(expiries[5], ethDefaultPrice + 61e18, conf);
    ethFeed.setForwardPrice(expiries[6], ethDefaultPrice + 63e18, conf);
    ethFeed.setForwardPrice(expiries[7], ethDefaultPrice + 66e18, conf);
    
    btcFeed.setForwardPrice(expiries[0], btcDefaultPrice + 12.78e18, conf);
    btcFeed.setForwardPrice(expiries[1], btcDefaultPrice + 39.66e18, conf);
    btcFeed.setForwardPrice(expiries[2], btcDefaultPrice + 66.56e18, conf);
    btcFeed.setForwardPrice(expiries[3], btcDefaultPrice + 220e18, conf);
    btcFeed.setForwardPrice(expiries[4], btcDefaultPrice + 838e18, conf);
    btcFeed.setForwardPrice(expiries[5], btcDefaultPrice + 865e18, conf);
    btcFeed.setForwardPrice(expiries[6], btcDefaultPrice + 893e18, conf);
    btcFeed.setForwardPrice(expiries[7], btcDefaultPrice + 929e18, conf);
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

  function _runTestCase(string memory name) internal returns (ISubAccounts.AssetBalance[] memory)
  {
    
    (ISubAccounts.AssetBalance[] memory balances, int _mmInteger, int _imInteger ) = _loadTestData(name);
    (int im, int mm, ) = manager.getMarginByBalances(balances, aliceAcc);

    assertEq(mm / 1e18, _mmInteger, string.concat("MM not match for case: ", name));
    assertEq(im / 1e18, _imInteger, string.concat("IM not match for case: ", name));
  }
  
  function _loadTestData(string memory name) internal returns (ISubAccounts.AssetBalance[] memory, int mm, int im)
  {
    string memory json = jsonParser.jsonFromRelPath("/test/risk-managers/unit-tests/StandardManager/test-cases-2.json");
    bytes memory testCaseDetail = json.parseRaw(name);
    TestCase memory testCase = abi.decode(testCaseDetail, (TestCase));

    uint totalAssets = testCase.options.length + testCase.perps.length;

    ISubAccounts.AssetBalance[] memory balances = new ISubAccounts.AssetBalance[](totalAssets);

    for (uint i = 0; i < testCase.options.length; i++) {

      Option memory option = testCase.options[i];

      uint128 strike = uint128(option.strike * 1e18);
      uint64 expiry = uint64(dateToExpiry[option.expiry]);

      if (expiry == 0) revert (string.concat("Unset date to expiry value: ", option.expiry));

      // set vol and its confidence for this expiry + strike
      if (equal(option.underlying, "eth")) {
        ethFeed.setVol(expiry, strike, 0.5e18, 1e18);
      } else {
        btcFeed.setVol(expiry, strike, 0.5e18, 1e18);
      }

      // fill in balance
      balances[i] = ISubAccounts.AssetBalance(
        equal(option.underlying, "eth") ? ethOption : btcOption,
        OptionEncoding.toSubId(
          expiry,
          strike,
          equal(option.typeOption, "call")
        ),
        option.amount
      );
    }

    for (uint i = 0; i < testCase.perps.length; i++) {
      Option memory perp = testCase.perps[i];

      if (equal(perp.underlying, "eth")) {
        balances[i + testCase.options.length] = ISubAccounts.AssetBalance(
          ethPerp,
          0,
          perp.amount
        );
      } else {
        balances[i + testCase.options.length] = ISubAccounts.AssetBalance(
          btcPerp,
          0,
          perp.amount
        );
      }
    }

    mm = testCase.result.mm;
    im = testCase.result.im;

    return (balances, mm, im);
  }

  function equal(string memory a, string memory b) internal pure returns (bool) {
    return keccak256(bytes(a)) == keccak256(bytes(b));
  }
}
