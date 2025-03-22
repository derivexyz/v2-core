// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import {SVITestParams} from "../../../../lib/lyra-utils/test/math/SVI.t.sol";
import "../../../shared/utils/JsonMechIO.sol";

import "lyra-utils/decimals/SignedDecimalMath.sol";
import "../../../../src/risk-managers/PMRM_2_1.sol";
import "../../../../src/interfaces/ISubAccounts.sol";
import "../../../shared/mocks/MockFeeds.sol";

import "../../../shared/mocks/MockFeeds.sol";

import "./utils/PMRM_2_1TestBase.sol";

import {Config} from "../../../config-test.sol";

import "forge-std/console.sol";

contract UNIT_TestPMRM_2_1_PortfolioCasesNEW is PMRM_2_1TestBase {
  using SignedDecimalMath for int;
  using stdJson for string;

  string constant FILE_PATH = "/test/risk-managers/unit-tests/PMRM_2_1/contract_results.json";

  JsonMechIO immutable jsonParser;

  uint mockAccIdToRequest = 0;

  string TEST_NAME;
  string JSON;
  uint REF_TIME;

  constructor() public {
    jsonParser = new JsonMechIO();
  }

  function test_1_collateral_cash_only() public {
    _runTestCase(".test_1_collateral_cash_only");
  }

  function test_2_collateral_usdt_only() public {
    _runTestCase(".test_2_collateral_usdt_only");
  }

  function test_3_collateral_multiple_stables() public {
    _runTestCase(".test_3_collateral_multiple_stables");
  }

  function test_4_collateral_multiple_lrts() public {
    _runTestCase(".test_4_collateral_multiple_lrts");
  }

  function test_5_collateral_general_multi_collat() public {
    _runTestCase(".test_5_collateral_general_multi_collat");
  }

  function test_6_collateral_general_multi_collat_with_oracle_cont() public {
    _runTestCase(".test_6_collateral_general_multi_collat_with_oracle_cont");
  }

  function test_7_collateral_only_base_risk_cancelling() public {
    _runTestCase(".test_7_collateral_only_base_risk_cancelling");
  }

  function test_8_collateral_only_base_risk_cancelling_2() public {
    _runTestCase(".test_8_collateral_only_base_risk_cancelling_2");
  }

  function test_9_collateral_general_revert_to_2() public {
    _runTestCase(".test_9_collateral_general_revert_to_2");
  }

  function test_10_collateral_negative_margin_from_collateral() public {
    _runTestCase(".test_10_collateral_negative_margin_from_collateral");
  }

  function test_11_collateral_usdc_depeg_only_cash() public {
    _runTestCase(".test_11_collateral_usdc_depeg_only_cash");
  }

  function test_12_risk_cancelling_naked_short_call() public {
    _runTestCase(".test_12_risk_cancelling_naked_short_call");
  }

  function test_13_risk_cancelling_btc_covered_call() public {
    _runTestCase(".test_13_risk_cancelling_btc_covered_call");
  }

  function test_14_risk_cancelling_lrt_covered_call() public {
    _runTestCase(".test_14_risk_cancelling_lrt_covered_call");
  }

  function test_15_risk_cancelling_eth_call_with_btc_collat() public {
    _runTestCase(".test_15_risk_cancelling_eth_call_with_btc_collat");
  }

  function test_16_risk_cancelling_general_covered_call() public {
    _runTestCase(".test_16_risk_cancelling_general_covered_call");
  }

  function test_17_risk_cancelling_revert_risk_cancelling_to_2() public {
    _runTestCase(".test_17_risk_cancelling_revert_risk_cancelling_to_2");
  }

  function test_18_structures_OTM_call_spread() public {
    _runTestCase(".test_18_structures_OTM_call_spread");
  }

  function test_19_structures_ITM_call_spread() public {
    _runTestCase(".test_19_structures_ITM_call_spread");
  }

  function test_20_structures_basic_put() public {
    _runTestCase(".test_20_structures_basic_put");
  }

  function test_21_structures_long_fly() public {
    _runTestCase(".test_21_structures_long_fly");
  }

  function test_22_structures_long_box() public {
    _runTestCase(".test_22_structures_long_box");
  }

  function test_23_structures_short_box() public {
    _runTestCase(".test_23_structures_short_box");
  }

  function test_24_structures_short_box_capped() public {
    _runTestCase(".test_24_structures_short_box_capped");
  }

  function test_25_structures_risk_reversal_dn() public {
    _runTestCase(".test_25_structures_risk_reversal_dn");
  }

  function test_26_structures_vega_neutral_fly() public {
    _runTestCase(".test_26_structures_vega_neutral_fly");
  }

  function test_27_structures_revert_20_short_box() public {
    _runTestCase(".test_27_structures_revert_20_short_box");
  }

  function test_28_structures_marking_up() public {
    _runTestCase(".test_28_structures_marking_up");
  }

  function test_29_perps_basic_perp() public {
    _runTestCase(".test_29_perps_basic_perp");
  }

  function test_30_perps_basic_perp_low_confidence() public {
    _runTestCase(".test_30_perps_basic_perp_low_confidence");
  }

  function test_31_perps_basic_perp_low_confidence_2() public {
    _runTestCase(".test_31_perps_basic_perp_low_confidence_2");
  }

  function test_32_perps_perp_hedging() public {
    _runTestCase(".test_32_perps_perp_hedging");
  }

  function test_33_perps_general_perp_hedging() public {
    _runTestCase(".test_33_perps_general_perp_hedging");
  }

  function test_34_tails_basic_tail_test() public {
    _runTestCase(".test_34_tails_basic_tail_test");
  }

  function test_35_tails_general_tail_test() public {
    _runTestCase(".test_35_tails_general_tail_test");
  }

  function test_36_tails_general_tail_test_2() public {
    _runTestCase(".test_36_tails_general_tail_test_2");
  }

  function test_37_tails_tails_revert_to_2() public {
    _runTestCase(".test_37_tails_tails_revert_to_2");
  }

  function test_38_tails_super_otm() public {
    _runTestCase(".test_38_tails_super_otm");
  }

  function test_39_tails_slightly_otm_call() public {
    _runTestCase(".test_39_tails_slightly_otm_call");
  }

  function test_40_tails_atm_tail_call_no_effect() public {
    _runTestCase(".test_40_tails_atm_tail_call_no_effect");
  }

  function test_41_skews_linear_as_worst_case_simple() public {
    _runTestCase(".test_41_skews_linear_as_worst_case_simple");
  }

  function test_42_skews_abs_as_worst_case_simple() public {
    _runTestCase(".test_42_skews_abs_as_worst_case_simple");
  }

  function test_43_skews_linear_as_worst_case_complex() public {
    _runTestCase(".test_43_skews_linear_as_worst_case_complex");
  }

  function test_44_skews_abs_as_worst_case_complex() public {
    _runTestCase(".test_44_skews_abs_as_worst_case_complex");
  }

  function test_45_skews_linear_skew_revert_to_2() public {
    _runTestCase(".test_45_skews_linear_skew_revert_to_2");
  }

  function test_46_v20_remnants_v20_test_2_long_call() public {
    _runTestCase(".test_46_v20_remnants_v20_test_2_long_call");
  }

  function test_47_v20_remnants_v20_test_3_itm_call_spread() public {
    _runTestCase(".test_47_v20_remnants_v20_test_3_itm_call_spread");
  }

  function test_48_v20_remnants_v20_test_5_low_BTC_conf_no_impact() public {
    _runTestCase(".test_48_v20_remnants_v20_test_5_low_BTC_conf_no_impact");
  }

  function test_49_v20_remnants_v20_test_6_low_perp_conf_no_impact() public {
    _runTestCase(".test_49_v20_remnants_v20_test_6_low_perp_conf_no_impact");
  }

  function test_50_discounting_simple_discounting() public {
    _runTestCase(".test_50_discounting_simple_discounting");
  }

  function test_51_discounting_simple_discounting_long() public {
    _runTestCase(".test_51_discounting_simple_discounting_long");
  }

  function test_52_discounting_multi_expiry_discounting() public {
    _runTestCase(".test_52_discounting_multi_expiry_discounting");
  }

  function test_53_discounting_turn_off_discounting() public {
    _runTestCase(".test_53_discounting_turn_off_discounting");
  }

  function test_54_discounting_cap_mark_up_discounting() public {
    _runTestCase(".test_54_discounting_cap_mark_up_discounting");
  }

  function test_55_forward_cont_forward_cont_1() public {
    _runTestCase(".test_55_forward_cont_forward_cont_1");
  }

  function test_56_forward_cont_forward_cont_2() public {
    _runTestCase(".test_56_forward_cont_forward_cont_2");
  }

  function test_57_min_shock_min_eval_vol_shock() public {
    _runTestCase(".test_57_min_shock_min_eval_vol_shock");
  }

  function test_58_min_shock_check_vol_bounded_at_0() public {
    _runTestCase(".test_58_min_shock_check_vol_bounded_at_0");
  }

  function test_59_settlement_near_expiry() public {
    _runTestCase(".test_59_settlement_near_expiry");
  }

  function test_60_general_general_test_1() public {
    _runTestCase(".test_60_general_general_test_1");
  }

  function test_61_general_random_2() public {
    _runTestCase(".test_61_general_random_2");
  }

  function test_62_general_random_3() public {
    _runTestCase(".test_62_general_random_3");
  }

  function test_63_general_random_4() public {
    _runTestCase(".test_63_general_random_4");
  }

  function test_64_general_random_5() public {
    _runTestCase(".test_64_general_random_5");
  }

  function test_65_misc_post_expiry() public {
    _runTestCase(".test_65_misc_post_expiry");
  }
  // REMOVED
  //  function test_66_misc_skew_scenario_with_spot_move() public {
  //    _runTestCase(".test_66_misc_skew_scenario_with_spot_move");
  //  }

  function test_67_misc_syn_forward() public {
    _runTestCase(".test_67_misc_syn_forward");
  }

  function test_68_misc_change_dte_min() public {
    _runTestCase(".test_68_misc_change_dte_min");
  }

  function test_69_misc_extreme_static_disc_neg_value() public {
    _runTestCase(".test_69_misc_extreme_static_disc_neg_value");
  }

  function _runTestCase(string memory testName) internal {
    TEST_NAME = testName;
    REF_TIME = 1630000000;
    JSON = jsonParser.jsonFromRelPath(FILE_PATH);
    vm.warp(REF_TIME);
    ISubAccounts.AssetBalance[] memory balances = _loadTestData();
    _checkResults(TEST_NAME, balances);
  }

  function _checkResults(string memory testName, ISubAccounts.AssetBalance[] memory balances) internal {
    PMRM_2_1.Portfolio memory portfolio = pmrm_2_1.arrangePortfolioByBalances(balances);

    _logPortfolio(portfolio, REF_TIME);
    _compareResults(portfolio);
  }

  function _compareResults(PMRM_2_1.Portfolio memory portfolio) internal {
    console.log();
    console.log("===== Other Results =====");

    // CollateralMTM
    int collateralMTM = 0;
    for (uint i = 0; i < portfolio.collaterals.length; i++) {
      collateralMTM += int(portfolio.collaterals[i].value);
    }
    assertApproxEqAbs(collateralMTM, _readBNInt(JSON, TEST_NAME, ".Result.CollateralMTM"), 1e10, "Collateral MTM");

    int optionMTM = 0;
    for (uint i = 0; i < portfolio.expiries.length; i++) {
      optionMTM += int(portfolio.expiries[i].mtm);
    }

    assertApproxEqRel(optionMTM, _readBNInt(JSON, TEST_NAME, ".Result.OptionMTM"), 1e10, "Option MTM");

    IPMRM_2_1.Scenario[] memory scenarios = pmrm_2_1.getScenarios();

    bool viewOne = true;
    uint scenarioToCheck = 0;

    uint regCount = 0;
    uint tailCount = 0;

    for (uint i = 0; i < scenarios.length; i++) {
      console.log("##### Scenario", i);
      if (scenarios[i].volShock == IPMRM_2_1.VolShockDirection.None) {
        _logBN("Vol shock: None - Spot shock: ", scenarios[i].spotShock);
      } else if (scenarios[i].volShock == IPMRM_2_1.VolShockDirection.Up) {
        _logBN("Vol shock: Up - Spot shock: ", scenarios[i].spotShock);
      } else if (scenarios[i].volShock == IPMRM_2_1.VolShockDirection.Down) {
        _logBN("Vol shock: Down - Spot shock: ", scenarios[i].spotShock);
      } else if (scenarios[i].volShock == IPMRM_2_1.VolShockDirection.Linear) {
        _logBN("Vol shock: Linear - Spot shock: ", scenarios[i].spotShock);
      } else if (scenarios[i].volShock == IPMRM_2_1.VolShockDirection.Abs) {
        _logBN("Vol shock: Abs - Spot shock: ", scenarios[i].spotShock);
      } else {
        console.log("Invalid vol shock", uint(scenarios[i].volShock));
        revert("Invalid vol shock");
      }
      _logBN("Dampening factor: ", scenarios[i].dampeningFactor);
      int scenarioMtM = lib.getScenarioMtM(portfolio, scenarios[i]);
      _logBN("Scenario MTM: ", scenarioMtM);

      string memory basePath = string.concat(TEST_NAME, ".Result.reg_losses[", vm.toString(i), "]");
      int scenarioLoss = 0;
      if (JSON.keyExists(basePath)) {
        regCount++;
        scenarioLoss = _readBNInt(JSON, basePath, "[2]");
      } else {
        basePath = string.concat(TEST_NAME, ".Result.tail_losses[", vm.toString(i - regCount), "]");
        if (JSON.keyExists(basePath)) {
          tailCount++;
          scenarioLoss = _readBNInt(JSON, basePath, "[2]");
        } else {
          basePath = string.concat(TEST_NAME, ".Result.skew_losses[", vm.toString(i - tailCount - regCount), "]");
          if (JSON.keyExists(basePath)) {
            scenarioLoss = _readBNInt(JSON, basePath, "[1]");
          } else {
            revert("No loss data for scenario");
          }
        }
      }

      _logBN("Expected MTM: ", scenarioLoss);
      if ((scenarioMtM < 1e8 && scenarioMtM > -1e8) || (scenarioLoss < 1e8 && scenarioLoss > -1e8)) {
        assertApproxEqAbs(scenarioMtM, scenarioLoss, 1e10, "Scenario MTM");
      } else {
        assertApproxEqRel(scenarioMtM, scenarioLoss, 1e10, "Scenario MTM");
      }
    }

    (int mm,,) = pmrm_2_1.getMarginAndMarkToMarketPub(portfolio, false, scenarios);
    assertApproxEqRel(mm, _readBNInt(JSON, TEST_NAME, ".Result.MM"), 1e10, "MM");

    (int im,,) = pmrm_2_1.getMarginAndMarkToMarketPub(portfolio, true, scenarios);
    assertApproxEqRel(im, _readBNInt(JSON, TEST_NAME, ".Result.IM"), 1e10, "IM");
  }

  ////////////////////////////////
  // Load data and get balances //
  ////////////////////////////////

  function _loadTestData() internal returns (ISubAccounts.AssetBalance[] memory bals) {
    // set params
    _setLibParams();
    _setScenarios();
    _setFeeds();

    // deploy collaterals and feeds
    ISubAccounts.AssetBalance[] memory collats = _loadCollateralData();
    ISubAccounts.AssetBalance[] memory options = _loadOptionData();
    bals = _loadAssets(collats, options);

    return bals;
  }

  function _setFeeds() internal {
    feed.setUseSVI(true);

    uint spot = _readBNUint(JSON, TEST_NAME, ".Scenario.SpotPrice");
    feed.setSpot(spot, _readBNUint(JSON, TEST_NAME, ".Scenario.SpotConfidence"));

    uint perpSpot = _readBNUint(JSON, TEST_NAME, ".Scenario.PerpPrice");

    mockPerp.setMockPerpPrice(perpSpot, _readBNUint(JSON, TEST_NAME, ".Scenario.PerpConfidence"));
    mockPerp.mockAccountPnlAndFunding(
      0,
      _readBNInt(JSON, TEST_NAME, ".Scenario.UnrealisedPerpPNL"),
      _readBNInt(JSON, TEST_NAME, ".Scenario.UnrealisedFunding")
    );

    console.log("Setting perp spot", perpSpot);
    console.log("perp conf", _readBNUint(JSON, TEST_NAME, ".Scenario.PerpConfidence"));

    stableFeed.setSpot(
      _readBNUint(JSON, TEST_NAME, ".Scenario.StablePrice"), _readBNUint(JSON, TEST_NAME, ".Scenario.StableConfidence")
    );

    uint expiryCount = 0;
    while (true) {
      string memory basePath = string.concat(TEST_NAME, ".Scenario.OptionFeeds[", vm.toString(expiryCount), "].");
      if (JSON.keyExists(string.concat(basePath, "FeedExpiry")) == false) {
        break;
      }

      uint secToExpiry = JSON.readUint(string.concat(basePath, "FeedExpiry"));
      uint expiry = REF_TIME + secToExpiry;

      feed.setVolSviParams(
        uint64(expiry),
        SVITestParams({
          a: _readBNInt(JSON, basePath, "[0]"),
          b: _readBNUint(JSON, basePath, "[1]"),
          rho: _readBNInt(JSON, basePath, "[2]"),
          m: _readBNInt(JSON, basePath, "[3]"),
          sigma: _readBNUint(JSON, basePath, "[4]"),
          forwardPrice: _readBNUint(JSON, basePath, "[5]"),
          tau: uint64(_readBNUint(JSON, basePath, "[6]"))
        }),
        _readBNUint(JSON, basePath, "OptionVolConfidences")
      );

      (uint vol,) = feed.getVol(95000e18, uint64(expiry));

      feed.setInterestRate(
        expiry, int96(_readBNInt(JSON, basePath, "Rate")), uint64(_readBNUint(JSON, basePath, "RateConfidence"))
      );

      uint fwdPrice = _readBNUint(JSON, basePath, "Forward");
      if (secToExpiry < 30 minutes) {
        feed.setForwardPricePortions(
          expiry,
          fwdPrice * (30 minutes - secToExpiry) / 30 minutes,
          fwdPrice * secToExpiry / 30 minutes,
          _readBNUint(JSON, basePath, "ForwardConfidence")
        );
      } else {
        feed.setForwardPrice(expiry, fwdPrice, _readBNUint(JSON, basePath, "ForwardConfidence"));
      }

      expiryCount++;
    }
  }

  function _loadAssets(ISubAccounts.AssetBalance[] memory options, ISubAccounts.AssetBalance[] memory collaterals)
    internal
    returns (ISubAccounts.AssetBalance[] memory)
  {
    uint assetCount = options.length + collaterals.length;

    int cashBal = int(_toBNUint(JSON.readString(string.concat(TEST_NAME, ".Scenario.Cash"))));
    int perpAmt = int(_toBNUint(JSON.readString(string.concat(TEST_NAME, ".Scenario.NumPerps"))));

    if (cashBal != 0) assetCount++;
    if (perpAmt != 0) assetCount++;

    ISubAccounts.AssetBalance[] memory res = new ISubAccounts.AssetBalance[](assetCount);

    uint i = 0;
    for (; i < options.length; i++) {
      res[i] = options[i];
    }
    for (; i < options.length + collaterals.length; i++) {
      res[i] = collaterals[i - options.length];
    }

    if (cashBal != 0) {
      res[i] = ISubAccounts.AssetBalance({asset: IAsset(address(cash)), subId: 0, balance: cashBal});
      i++;
    }

    if (perpAmt != 0) {
      res[i] = ISubAccounts.AssetBalance({asset: IAsset(address(mockPerp)), subId: 0, balance: perpAmt});
    }

    return res;
  }

  function _loadOptionData() internal returns (ISubAccounts.AssetBalance[] memory) {
    uint optionCount = 0;
    while (true) {
      if (JSON.keyExists(string.concat(TEST_NAME, ".Scenario.Options[", vm.toString(optionCount), "].Expiry")) == false)
      {
        break;
      }
      optionCount++;
    }

    // Get number of options

    ISubAccounts.AssetBalance[] memory res = new ISubAccounts.AssetBalance[](optionCount);

    // Load each option

    for (uint i = 0; i < optionCount; i++) {
      string memory basePath = string.concat(TEST_NAME, ".Scenario.Options[", vm.toString(i), "].");

      uint expiry = REF_TIME + JSON.readUint(string.concat(basePath, "Expiry"));
      uint strike = _toBNUint(JSON.readString(string.concat(basePath, "Strike")));
      bool isCall = JSON.readBool(string.concat(basePath, "IsCall"));

      res[i] = ISubAccounts.AssetBalance({
        asset: IAsset(address(option)),
        subId: OptionEncoding.toSubId(expiry, strike, isCall),
        balance: int(_toBNUint(JSON.readString(string.concat(basePath, "Amount"))))
      });
    }

    return res;
  }

  function _loadCollateralData() internal returns (ISubAccounts.AssetBalance[] memory) {
    uint collatCount = 0;
    while (true) {
      if (
        JSON.keyExists(string.concat(TEST_NAME, ".Scenario.Collaterals[", vm.toString(collatCount), "].Name")) == false
      ) {
        break;
      }
      collatCount++;
    }

    // Get number of collaterals

    ISubAccounts.AssetBalance[] memory res = new ISubAccounts.AssetBalance[](collatCount);

    // Load each collateral

    for (uint i = 0; i < collatCount; i++) {
      string memory basePath = string.concat(TEST_NAME, ".Scenario.Collaterals[", vm.toString(i), "].");

      string memory name = JSON.readString(string.concat(basePath, "Name"));

      IPMRMLib_2_1.CollateralParameters memory collatParams = IPMRMLib_2_1.CollateralParameters({
        isRiskCancelling: JSON.readBool(string.concat(basePath, "IsRiskCancelling")),
        MMHaircut: _readBNUint(JSON, basePath, "MMHaircut"),
        IMHaircut: _readBNUint(JSON, basePath, "IMHaircut")
      });

      MockERC20 erc20 = new MockERC20(name, name);
      WrappedERC20Asset wAsset = new WrappedERC20Asset(subAccounts, erc20);
      MockFeeds newFeed = new MockFeeds();

      assetLabel[address(wAsset)] = name;

      newFeed.setSpot(_readBNUint(JSON, basePath, "Price"), _readBNUint(JSON, basePath, "Confidence"));

      pmrm_2_1.setCollateralSpotFeed(address(wAsset), newFeed);
      lib.setCollateralParameters(address(wAsset), collatParams);

      uint amount = _toBNUint(JSON.readString(string.concat(basePath, "Amount")));

      res[i] = ISubAccounts.AssetBalance({asset: IAsset(address(wAsset)), subId: 0, balance: int(amount)});
    }

    return res;
  }

  function _setScenarios() internal {
    uint scenariosCount = 0;
    while (true) {
      if (JSON.keyExists(string.concat(TEST_NAME, ".Parameters.Scenarios[", vm.toString(scenariosCount), "]")) == false)
      {
        break;
      }
      scenariosCount++;
    }

    IPMRM_2_1.Scenario[] memory scenarios = new IPMRM_2_1.Scenario[](scenariosCount);
    for (uint i = 0; i < scenariosCount; i++) {
      string memory basePath = string.concat(TEST_NAME, ".Parameters.Scenarios[", vm.toString(i), "].");
      string memory shockDirection = JSON.readString(string.concat(basePath, "VolShockDirection"));
      IPMRM_2_1.VolShockDirection volShockDirection = IPMRM_2_1.VolShockDirection.None;
      if (keccak256(abi.encodePacked(shockDirection)) == keccak256(abi.encodePacked("Up"))) {
        volShockDirection = IPMRM_2_1.VolShockDirection.Up;
      } else if (keccak256(abi.encodePacked(shockDirection)) == keccak256(abi.encodePacked("Down"))) {
        volShockDirection = IPMRM_2_1.VolShockDirection.Down;
      } else if (keccak256(abi.encodePacked(shockDirection)) == keccak256(abi.encodePacked("LINEAR"))) {
        volShockDirection = IPMRM_2_1.VolShockDirection.Linear;
      } else if (keccak256(abi.encodePacked(shockDirection)) == keccak256(abi.encodePacked("ABS"))) {
        volShockDirection = IPMRM_2_1.VolShockDirection.Abs;
      } else if (keccak256(abi.encodePacked(shockDirection)) == keccak256(abi.encodePacked("None"))) {
        volShockDirection = IPMRM_2_1.VolShockDirection.None;
      } else {
        console.log("Invalid shock direction: ", shockDirection);
        revert("Invalid shock direction");
      }
      scenarios[i] = IPMRM_2_1.Scenario({
        spotShock: _readBNUint(JSON, basePath, "SpotShock"),
        volShock: volShockDirection,
        dampeningFactor: _readBNUint(JSON, basePath, "DampeningFactor")
      });
    }

    pmrm_2_1.setScenarios(scenarios);
  }

  function _setLibParams() internal {
    lib.setVolShockParams(
      IPMRMLib_2_1.VolShockParameters({
        volRangeUp: _readBNUint(JSON, TEST_NAME, ".Parameters.VolShock.VOLRANGEUP"),
        volRangeDown: _readBNUint(JSON, TEST_NAME, ".Parameters.VolShock.VOLRANGEDOWN"),
        shortTermPower: _readBNInt(JSON, TEST_NAME, ".Parameters.VolShock.SHORTTERMPOWER"),
        longTermPower: _readBNInt(JSON, TEST_NAME, ".Parameters.VolShock.LONGTERMPOWER"),
        dteFloor: _readBNUint(JSON, TEST_NAME, ".Parameters.VolShock.DTE_FLOOR") * 1 days / 1e18,
        minVolUpShock: _readBNUint(JSON, TEST_NAME, ".Parameters.VolShock.MIN_VOL_EVAL_SHOCKED")
      })
    );

    lib.setMarginParams(
      IPMRMLib_2_1.MarginParameters({
        imFactor: _readBNUint(JSON, TEST_NAME, ".Parameters.Margin.IM_LOSS_FACTOR"),
        mmFactor: _readBNUint(JSON, TEST_NAME, ".Parameters.Margin.MM_LOSS_FACTOR"),
        shortRateMultScale: _readBNUint(JSON, TEST_NAME, ".Parameters.Margin.SHORT_RATE_MULTSCALE"),
        longRateMultScale: _readBNUint(JSON, TEST_NAME, ".Parameters.Margin.LONG_RATE_MULTSCALE"),
        shortRateAddScale: _readBNUint(JSON, TEST_NAME, ".Parameters.Margin.SHORT_RATE_ADDSCALE"),
        longRateAddScale: _readBNUint(JSON, TEST_NAME, ".Parameters.Margin.LONG_RATE_ADDSCALE"),
        shortBaseStaticDiscount: _readBNUint(JSON, TEST_NAME, ".Parameters.Margin.BASE_STATIC_DISCOUNT_NEG"),
        longBaseStaticDiscount: _readBNUint(JSON, TEST_NAME, ".Parameters.Margin.BASE_STATIC_DISCOUNT")
      })
    );

    lib.setBasisContingencyParams(
      IPMRMLib_2_1.BasisContingencyParameters({
        scenarioSpotUp: _readBNUint(JSON, TEST_NAME, ".Parameters.BasisContingency.SCENARIO_SPOT_UP"),
        scenarioSpotDown: _readBNUint(JSON, TEST_NAME, ".Parameters.BasisContingency.SCENARIO_SPOT_DOWN"),
        basisContAddFactor: _readBNUint(JSON, TEST_NAME, ".Parameters.BasisContingency.BASIS_CONT_ADD_FACTOR"),
        basisContMultFactor: _readBNUint(JSON, TEST_NAME, ".Parameters.BasisContingency.BASIS_CONT_MULT_FACTOR")
      })
    );

    lib.setOtherContingencyParams(
      IPMRMLib_2_1.OtherContingencyParameters({
        pegLossThreshold: _readBNUint(JSON, TEST_NAME, ".Parameters.OtherContingency.PEG_LOSS_THRESHOLD"),
        pegLossFactor: _readBNUint(JSON, TEST_NAME, ".Parameters.OtherContingency.PEG_LOSS_FACTOR"),
        confThreshold: _readBNUint(JSON, TEST_NAME, ".Parameters.OtherContingency.CONF_THRESHOLD"),
        confMargin: _readBNUint(JSON, TEST_NAME, ".Parameters.OtherContingency.CONF_MARGIN"),
        MMPerpPercent: _readBNUint(JSON, TEST_NAME, ".Parameters.OtherContingency.MM_PERP_PERCENT"),
        IMPerpPercent: _readBNUint(JSON, TEST_NAME, ".Parameters.OtherContingency.IM_PERP_PERCENT"),
        MMOptionPercent: _readBNUint(JSON, TEST_NAME, ".Parameters.OtherContingency.MM_OPTION_PERCENT"),
        IMOptionPercent: _readBNUint(JSON, TEST_NAME, ".Parameters.OtherContingency.IM_OPTION_PERCENT")
      })
    );

    lib.setSkewShockParameters(
      IPMRMLib_2_1.SkewShockParameters({
        linearBaseCap: _readBNUint(JSON, TEST_NAME, ".Parameters.SkewShock.LINEAR_SCALE_CAP"),
        absBaseCap: _readBNUint(JSON, TEST_NAME, ".Parameters.SkewShock.ABS_SCALE_CAP"),
        linearCBase: _readBNInt(JSON, TEST_NAME, ".Parameters.SkewShock.LINEAR_CBASE"),
        absCBase: _readBNInt(JSON, TEST_NAME, ".Parameters.SkewShock.ABS_CBASE"),
        minKStar: _readBNInt(JSON, TEST_NAME, ".Parameters.SkewShock.MIN_K_STAR"),
        widthScale: _readBNInt(JSON, TEST_NAME, ".Parameters.SkewShock.MIN_WIDTH_SCALE"),
        volParamStatic: _readBNInt(JSON, TEST_NAME, ".Parameters.SkewShock.VOL_PARAM_STATIC"),
        volParamScale: _readBNInt(JSON, TEST_NAME, ".Parameters.SkewShock.VOL_PARAM_SCALE")
      })
    );
  }

  /////////////
  // Helpers //
  /////////////

  function _readBNUint(string memory json, string memory basePath, string memory key) internal returns (uint) {
    return _toBNUint(json.readString(string.concat(basePath, key)));
  }

  function _readBNInt(string memory json, string memory basePath, string memory key) internal returns (int) {
    return _toBNInt(json.readString(string.concat(basePath, key)));
  }

  function _toBNUint(string memory floatString) internal pure returns (uint) {
    return uint(_toBNInt(floatString));
  }

  function _toBNInt(string memory floatString) internal pure returns (int) {
    bytes memory strBytes = bytes(floatString);
    bool negative = false;
    uint startIndex = 0;

    // Check for negative sign
    if (strBytes.length > 0 && strBytes[0] == "-") {
      negative = true;
      startIndex = 1;
    }

    // Find decimal point position
    int decimalPos = -1;
    for (uint i = startIndex; i < strBytes.length; i++) {
      if (strBytes[i] == ".") {
        decimalPos = int(i);
        break;
      }
    }

    // Calculate the integer part
    int result = 0;
    for (uint i = startIndex; i < strBytes.length; i++) {
      if (i == uint(decimalPos)) continue;

      bytes1 char = strBytes[i];
      if (char >= bytes1("0") && char <= bytes1("9")) {
        // If we're past decimal, we're adding decimals
        if (decimalPos != -1 && int(i) > decimalPos) {
          result = result * 10 + (int(int8(uint8(char))) - 48);
        }
        // Otherwise adding to the integer part
        else if (decimalPos == -1 || int(i) < decimalPos) {
          result = result * 10 + (int(int8(uint8(char))) - 48);
        }
      }
    }

    // Scale result to 18 decimals
    if (decimalPos == -1) {
      // No decimal point, just add 18 zeros
      result *= 10 ** 18;
    } else {
      uint decimalPlaces = (decimalPos == -1) ? 0 : strBytes.length - uint(decimalPos) - 1;
      if (decimalPlaces < 18) {
        result *= int(10 ** (18 - decimalPlaces));
      } else if (decimalPlaces > 18) {
        // If there are more than 18 decimals, truncate
        result /= int(10 ** (decimalPlaces - 18));
      }
    }

    // Apply negative sign if needed
    if (negative) {
      result = -result;
    }

    return result;
  }
}
