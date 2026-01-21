// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import {SVITestParams} from "lyra-utils-test/math/SVI.t.sol";
import "../../../shared/utils/JsonMechIO.sol";

import "lyra-utils/decimals/SignedDecimalMath.sol";
import "../../../../src/risk-managers/PMRM_2.sol";
import "../../../../src/interfaces/ISubAccounts.sol";
import "../../../shared/mocks/MockFeeds.sol";

import "../../../shared/mocks/MockFeeds.sol";

import "./utils/PMRM_2TestBase.sol";

import {Config} from "../../../config-test.sol";

import "forge-std/console.sol";

contract UNIT_TestPMRM_2_PortfolioCasesNEW is PMRM_2TestBase {
  using SignedDecimalMath for int;
  using stdJson for string;

  string constant FILE_PATH = "/test/risk-managers/unit-tests/PMRM_2/portfolio_cases";

  JsonMechIO immutable jsonParser;

  uint mockAccIdToRequest = 0;

  string TEST_NAME;
  string JSON;
  uint REF_TIME;

  constructor() public {
    jsonParser = new JsonMechIO();
  }

  function test_1_collateral_cash_only() public {
    _runTestCase("test_1_collateral_cash_only");
  }

  function test_2_collateral_usdt_only() public {
    _runTestCase("test_2_collateral_usdt_only");
  }

  function test_3_collateral_multiple_stables() public {
    _runTestCase("test_3_collateral_multiple_stables");
  }

  function test_4_collateral_multiple_lrts() public {
    _runTestCase("test_4_collateral_multiple_lrts");
  }

  function test_5_collateral_general_multi_collat() public {
    _runTestCase("test_5_collateral_general_multi_collat");
  }

  function test_6_collateral_general_multi_collat_with_oracle_cont() public {
    _runTestCase("test_6_collateral_general_multi_collat_with_oracle_cont");
  }

  function test_7_collateral_only_base_risk_cancelling() public {
    _runTestCase("test_7_collateral_only_base_risk_cancelling");
  }

  function test_8_collateral_only_base_risk_cancelling_2() public {
    _runTestCase("test_8_collateral_only_base_risk_cancelling_2");
  }

  function test_9_collateral_general_revert_to_2() public {
    _runTestCase("test_9_collateral_general_revert_to_2");
  }

  function test_10_collateral_negative_margin_from_collateral() public {
    _runTestCase("test_10_collateral_negative_margin_from_collateral");
  }

  function test_11_collateral_usdc_depeg_only_cash() public {
    _runTestCase("test_11_collateral_usdc_depeg_only_cash");
  }

  function test_12_risk_cancelling_naked_short_call() public {
    _runTestCase("test_12_risk_cancelling_naked_short_call");
  }

  function test_13_risk_cancelling_btc_covered_call() public {
    _runTestCase("test_13_risk_cancelling_btc_covered_call");
  }

  function test_14_risk_cancelling_lrt_covered_call() public {
    _runTestCase("test_14_risk_cancelling_lrt_covered_call");
  }

  function test_15_risk_cancelling_eth_call_with_btc_collat() public {
    _runTestCase("test_15_risk_cancelling_eth_call_with_btc_collat");
  }

  function test_16_risk_cancelling_general_covered_call() public {
    _runTestCase("test_16_risk_cancelling_general_covered_call");
  }

  function test_17_risk_cancelling_revert_risk_cancelling_to_2() public {
    _runTestCase("test_17_risk_cancelling_revert_risk_cancelling_to_2");
  }

  function test_18_structures_OTM_call_spread() public {
    _runTestCase("test_18_structures_OTM_call_spread");
  }

  function test_19_structures_ITM_call_spread() public {
    _runTestCase("test_19_structures_ITM_call_spread");
  }

  function test_20_structures_basic_put() public {
    _runTestCase("test_20_structures_basic_put");
  }

  function test_21_structures_long_fly() public {
    _runTestCase("test_21_structures_long_fly");
  }

  function test_22_structures_long_box() public {
    _runTestCase("test_22_structures_long_box");
  }

  function test_23_structures_short_box() public {
    _runTestCase("test_23_structures_short_box");
  }

  function test_24_structures_short_box_capped() public {
    _runTestCase("test_24_structures_short_box_capped");
  }

  function test_25_structures_risk_reversal_dn() public {
    _runTestCase("test_25_structures_risk_reversal_dn");
  }

  function test_26_structures_vega_neutral_fly() public {
    _runTestCase("test_26_structures_vega_neutral_fly");
  }

  function test_27_structures_revert_20_short_box() public {
    _runTestCase("test_27_structures_revert_20_short_box");
  }

  function test_28_structures_marking_up() public {
    _runTestCase("test_28_structures_marking_up");
  }

  function test_29_perps_basic_perp() public {
    _runTestCase("test_29_perps_basic_perp");
  }

  function test_30_perps_basic_perp_low_confidence() public {
    _runTestCase("test_30_perps_basic_perp_low_confidence");
  }

  function test_31_perps_basic_perp_low_confidence_2() public {
    _runTestCase("test_31_perps_basic_perp_low_confidence_2");
  }

  function test_32_perps_perp_hedging() public {
    _runTestCase("test_32_perps_perp_hedging");
  }

  function test_33_perps_general_perp_hedging() public {
    _runTestCase("test_33_perps_general_perp_hedging");
  }

  function test_34_tails_basic_tail_test() public {
    _runTestCase("test_34_tails_basic_tail_test");
  }

  function test_35_tails_general_tail_test() public {
    _runTestCase("test_35_tails_general_tail_test");
  }

  function test_36_tails_general_tail_test_2() public {
    _runTestCase("test_36_tails_general_tail_test_2");
  }

  function test_37_tails_tails_revert_to_2() public {
    _runTestCase("test_37_tails_tails_revert_to_2");
  }

  function test_38_tails_super_otm() public {
    _runTestCase("test_38_tails_super_otm");
  }

  function test_39_tails_slightly_otm_call() public {
    _runTestCase("test_39_tails_slightly_otm_call");
  }

  function test_40_tails_atm_tail_call_no_effect() public {
    _runTestCase("test_40_tails_atm_tail_call_no_effect");
  }

  function test_41_skews_linear_as_worst_case_simple() public {
    _runTestCase("test_41_skews_linear_as_worst_case_simple");
  }

  function test_42_skews_abs_as_worst_case_simple() public {
    _runTestCase("test_42_skews_abs_as_worst_case_simple");
  }

  function test_43_skews_linear_as_worst_case_complex() public {
    _runTestCase("test_43_skews_linear_as_worst_case_complex");
  }

  function test_44_skews_abs_as_worst_case_complex() public {
    _runTestCase("test_44_skews_abs_as_worst_case_complex");
  }

  function test_45_skews_linear_skew_revert_to_2() public {
    _runTestCase("test_45_skews_linear_skew_revert_to_2");
  }

  function test_46_v20_remnants_v20_test_2_long_call() public {
    _runTestCase("test_46_v20_remnants_v20_test_2_long_call");
  }

  function test_47_v20_remnants_v20_test_3_itm_call_spread() public {
    _runTestCase("test_47_v20_remnants_v20_test_3_itm_call_spread");
  }

  function test_48_v20_remnants_v20_test_5_low_BTC_conf_no_impact() public {
    _runTestCase("test_48_v20_remnants_v20_test_5_low_BTC_conf_no_impact");
  }

  function test_49_v20_remnants_v20_test_6_low_perp_conf_no_impact() public {
    _runTestCase("test_49_v20_remnants_v20_test_6_low_perp_conf_no_impact");
  }

  function test_50_discounting_simple_discounting() public {
    _runTestCase("test_50_discounting_simple_discounting");
  }

  function test_51_discounting_simple_discounting_long() public {
    _runTestCase("test_51_discounting_simple_discounting_long");
  }

  function test_52_discounting_multi_expiry_discounting() public {
    _runTestCase("test_52_discounting_multi_expiry_discounting");
  }

  function test_53_discounting_turn_off_discounting() public {
    _runTestCase("test_53_discounting_turn_off_discounting");
  }

  function test_54_discounting_cap_mark_up_discounting() public {
    _runTestCase("test_54_discounting_cap_mark_up_discounting");
  }

  function test_55_discounting_negative_rate() public {
    _runTestCase("test_55_discounting_negative_rate");
  }

  function test_56_forward_cont_forward_cont_1() public {
    _runTestCase("test_56_forward_cont_forward_cont_1");
  }

  function test_57_forward_cont_forward_cont_2() public {
    _runTestCase("test_57_forward_cont_forward_cont_2");
  }

  function test_58_min_shock_min_eval_vol_shock() public {
    _runTestCase("test_58_min_shock_min_eval_vol_shock");
  }

  function test_59_min_shock_check_vol_bounded_at_0() public {
    _runTestCase("test_59_min_shock_check_vol_bounded_at_0");
  }

  function test_60_settlement_near_expiry() public {
    _runTestCase("test_60_settlement_near_expiry");
  }

  function test_61_general_general_test_1() public {
    _runTestCase("test_61_general_general_test_1");
  }

  function test_62_general_random_2() public {
    _runTestCase("test_62_general_random_2");
  }

  function test_63_general_random_3() public {
    _runTestCase("test_63_general_random_3");
  }

  function test_64_general_random_4() public {
    _runTestCase("test_64_general_random_4");
  }

  function test_65_general_random_5() public {
    _runTestCase("test_65_general_random_5");
  }

  function test_66_misc_post_expiry() public {
    _runTestCase("test_66_misc_post_expiry");
  }

  // Invalid param setup so skipping
  //  function test_67_misc_skew_scenario_with_spot_move() public {
  //    _runTestCase("test_67_misc_skew_scenario_with_spot_move");
  //  }

  function test_68_misc_syn_forward() public {
    _runTestCase("test_68_misc_syn_forward");
  }

  function test_69_misc_change_dte_min() public {
    _runTestCase("test_69_misc_change_dte_min");
  }

  function test_70_misc_extreme_static_disc_neg_value() public {
    _runTestCase("test_70_misc_extreme_static_disc_neg_value");
  }

  function test_71_misc_super_itm_spread() public {
    _runTestCase("test_71_misc_super_itm_spread");
  }

  function test_72_VolShockParameters_VOLRANGEUP_min() public {
    _runTestCase("test_72_VolShockParameters_VOLRANGEUP_min");
  }

  function test_73_VolShockParameters_VOLRANGEUP_max() public {
    _runTestCase("test_73_VolShockParameters_VOLRANGEUP_max");
  }

  function test_74_VolShockParameters_VOLRANGEDOWN_min() public {
    _runTestCase("test_74_VolShockParameters_VOLRANGEDOWN_min");
  }

  function test_75_VolShockParameters_VOLRANGEDOWN_max() public {
    _runTestCase("test_75_VolShockParameters_VOLRANGEDOWN_max");
  }

  function test_76_VolShockParameters_SHORTTERMPOWER_min() public {
    _runTestCase("test_76_VolShockParameters_SHORTTERMPOWER_min");
  }

  function test_77_VolShockParameters_SHORTTERMPOWER_max() public {
    _runTestCase("test_77_VolShockParameters_SHORTTERMPOWER_max");
  }

  function test_78_VolShockParameters_LONGTERMPOWER_min() public {
    _runTestCase("test_78_VolShockParameters_LONGTERMPOWER_min");
  }

  function test_79_VolShockParameters_LONGTERMPOWER_max() public {
    _runTestCase("test_79_VolShockParameters_LONGTERMPOWER_max");
  }

  function test_80_VolShockParameters_DTE_FLOOR_min() public {
    _runTestCase("test_80_VolShockParameters_DTE_FLOOR_min");
  }

  function test_81_VolShockParameters_DTE_FLOOR_max() public {
    _runTestCase("test_81_VolShockParameters_DTE_FLOOR_max");
  }

  function test_82_VolShockParameters_MIN_VOL_EVAL_SHOCKED_min() public {
    _runTestCase("test_82_VolShockParameters_MIN_VOL_EVAL_SHOCKED_min");
  }

  function test_83_VolShockParameters_MIN_VOL_EVAL_SHOCKED_max() public {
    _runTestCase("test_83_VolShockParameters_MIN_VOL_EVAL_SHOCKED_max");
  }

  function test_84_MarginParameters_IM_LOSS_FACTOR_min() public {
    _runTestCase("test_84_MarginParameters_IM_LOSS_FACTOR_min");
  }

  function test_85_MarginParameters_IM_LOSS_FACTOR_max() public {
    _runTestCase("test_85_MarginParameters_IM_LOSS_FACTOR_max");
  }

  function test_86_MarginParameters_MM_LOSS_FACTOR_min() public {
    _runTestCase("test_86_MarginParameters_MM_LOSS_FACTOR_min");
  }

  function test_87_MarginParameters_MM_LOSS_FACTOR_max() public {
    _runTestCase("test_87_MarginParameters_MM_LOSS_FACTOR_max");
  }

  function test_88_MarginParameters_RFR_FACTOR1_NEG_min() public {
    _runTestCase("test_88_MarginParameters_RFR_FACTOR1_NEG_min");
  }

  function test_89_MarginParameters_RFR_FACTOR1_NEG_max() public {
    _runTestCase("test_89_MarginParameters_RFR_FACTOR1_NEG_max");
  }

  function test_90_MarginParameters_RFR_FACTOR1_POS_min() public {
    _runTestCase("test_90_MarginParameters_RFR_FACTOR1_POS_min");
  }

  function test_91_MarginParameters_RFR_FACTOR1_POS_max() public {
    _runTestCase("test_91_MarginParameters_RFR_FACTOR1_POS_max");
  }

  function test_92_MarginParameters_RFR_FACTOR2_NEG_min() public {
    _runTestCase("test_92_MarginParameters_RFR_FACTOR2_NEG_min");
  }

  function test_93_MarginParameters_RFR_FACTOR2_NEG_max() public {
    _runTestCase("test_93_MarginParameters_RFR_FACTOR2_NEG_max");
  }

  function test_94_MarginParameters_RFR_FACTOR2_POS_min() public {
    _runTestCase("test_94_MarginParameters_RFR_FACTOR2_POS_min");
  }

  function test_95_MarginParameters_RFR_FACTOR2_POS_max() public {
    _runTestCase("test_95_MarginParameters_RFR_FACTOR2_POS_max");
  }

  function test_96_MarginParameters_STATIC_DISCOUNT_min() public {
    _runTestCase("test_96_MarginParameters_STATIC_DISCOUNT_min");
  }

  function test_97_MarginParameters_STATIC_DISCOUNT_max() public {
    _runTestCase("test_97_MarginParameters_STATIC_DISCOUNT_max");
  }

  function test_98_MarginParameters_STATIC_DISCOUNT_NEG_min() public {
    _runTestCase("test_98_MarginParameters_STATIC_DISCOUNT_NEG_min");
  }

  function test_99_MarginParameters_STATIC_DISCOUNT_NEG_max() public {
    _runTestCase("test_99_MarginParameters_STATIC_DISCOUNT_NEG_max");
  }

  function test_100_BasisContingencyParameters_FWD_CONT_SHOCK_UP_min() public {
    _runTestCase("test_100_BasisContingencyParameters_FWD_CONT_SHOCK_UP_min");
  }

  function test_101_BasisContingencyParameters_FWD_CONT_SHOCK_UP_max() public {
    _runTestCase("test_101_BasisContingencyParameters_FWD_CONT_SHOCK_UP_max");
  }

  function test_102_BasisContingencyParameters_FWD_CONT_SHOCK_DOWN_min() public {
    _runTestCase("test_102_BasisContingencyParameters_FWD_CONT_SHOCK_DOWN_min");
  }

  function test_103_BasisContingencyParameters_FWD_CONT_SHOCK_DOWN_max() public {
    _runTestCase("test_103_BasisContingencyParameters_FWD_CONT_SHOCK_DOWN_max");
  }

  function test_104_BasisContingencyParameters_ADD_FACTOR_min() public {
    _runTestCase("test_104_BasisContingencyParameters_ADD_FACTOR_min");
  }

  function test_105_BasisContingencyParameters_ADD_FACTOR_max() public {
    _runTestCase("test_105_BasisContingencyParameters_ADD_FACTOR_max");
  }

  function test_106_BasisContingencyParameters_MULT_FACTOR_min() public {
    _runTestCase("test_106_BasisContingencyParameters_MULT_FACTOR_min");
  }

  function test_107_BasisContingencyParameters_MULT_FACTOR_max() public {
    _runTestCase("test_107_BasisContingencyParameters_MULT_FACTOR_max");
  }

  function test_108_OtherContingencyParameters_PEG_LOSS_THRESHOLD_min() public {
    _runTestCase("test_108_OtherContingencyParameters_PEG_LOSS_THRESHOLD_min");
  }

  function test_109_OtherContingencyParameters_PEG_LOSS_THRESHOLD_max() public {
    _runTestCase("test_109_OtherContingencyParameters_PEG_LOSS_THRESHOLD_max");
  }

  function test_110_OtherContingencyParameters_PEG_LOSS_FACTOR_min() public {
    _runTestCase("test_110_OtherContingencyParameters_PEG_LOSS_FACTOR_min");
  }

  function test_111_OtherContingencyParameters_PEG_LOSS_FACTOR_max() public {
    _runTestCase("test_111_OtherContingencyParameters_PEG_LOSS_FACTOR_max");
  }

  function test_112_OtherContingencyParameters_THRESHOLD_CONFIDENCE_min() public {
    _runTestCase("test_112_OtherContingencyParameters_THRESHOLD_CONFIDENCE_min");
  }

  function test_113_OtherContingencyParameters_THRESHOLD_CONFIDENCE_max() public {
    _runTestCase("test_113_OtherContingencyParameters_THRESHOLD_CONFIDENCE_max");
  }

  function test_114_OtherContingencyParameters_CONFIDENCE_SCALE_min() public {
    _runTestCase("test_114_OtherContingencyParameters_CONFIDENCE_SCALE_min");
  }

  function test_115_OtherContingencyParameters_CONFIDENCE_SCALE_max() public {
    _runTestCase("test_115_OtherContingencyParameters_CONFIDENCE_SCALE_max");
  }

  function test_116_OtherContingencyParameters_MMPerpPercent_min() public {
    _runTestCase("test_116_OtherContingencyParameters_MMPerpPercent_min");
  }

  function test_117_OtherContingencyParameters_MMPerpPercent_max() public {
    _runTestCase("test_117_OtherContingencyParameters_MMPerpPercent_max");
  }

  function test_118_OtherContingencyParameters_IMPerpPercent_min() public {
    _runTestCase("test_118_OtherContingencyParameters_IMPerpPercent_min");
  }

  function test_119_OtherContingencyParameters_IMPerpPercent_max() public {
    _runTestCase("test_119_OtherContingencyParameters_IMPerpPercent_max");
  }

  function test_120_OtherContingencyParameters_MMOptionPercent_min() public {
    _runTestCase("test_120_OtherContingencyParameters_MMOptionPercent_min");
  }

  function test_121_OtherContingencyParameters_MMOptionPercent_max() public {
    _runTestCase("test_121_OtherContingencyParameters_MMOptionPercent_max");
  }

  function test_122_OtherContingencyParameters_IMOptionPercent_min() public {
    _runTestCase("test_122_OtherContingencyParameters_IMOptionPercent_min");
  }

  function test_123_OtherContingencyParameters_IMOptionPercent_max() public {
    _runTestCase("test_123_OtherContingencyParameters_IMOptionPercent_max");
  }

  function test_124_SkewShockParameters_LINEAR_SCALE_CAP_min() public {
    _runTestCase("test_124_SkewShockParameters_LINEAR_SCALE_CAP_min");
  }

  function test_125_SkewShockParameters_LINEAR_SCALE_CAP_max() public {
    _runTestCase("test_125_SkewShockParameters_LINEAR_SCALE_CAP_max");
  }

  function test_126_SkewShockParameters_ABS_SCALE_CAP_min() public {
    _runTestCase("test_126_SkewShockParameters_ABS_SCALE_CAP_min");
  }

  function test_127_SkewShockParameters_ABS_SCALE_CAP_max() public {
    _runTestCase("test_127_SkewShockParameters_ABS_SCALE_CAP_max");
  }

  function test_128_SkewShockParameters_LINEAR_CBASE_min() public {
    _runTestCase("test_128_SkewShockParameters_LINEAR_CBASE_min");
  }

  function test_129_SkewShockParameters_LINEAR_CBASE_max() public {
    _runTestCase("test_129_SkewShockParameters_LINEAR_CBASE_max");
  }

  function test_130_SkewShockParameters_ABS_CBASE_min() public {
    _runTestCase("test_130_SkewShockParameters_ABS_CBASE_min");
  }

  function test_131_SkewShockParameters_ABS_CBASE_max() public {
    _runTestCase("test_131_SkewShockParameters_ABS_CBASE_max");
  }

  function test_132_SkewShockParameters_MIN_K_STAR_min() public {
    _runTestCase("test_132_SkewShockParameters_MIN_K_STAR_min");
  }

  function test_133_SkewShockParameters_MIN_K_STAR_max() public {
    _runTestCase("test_133_SkewShockParameters_MIN_K_STAR_max");
  }

  function test_134_SkewShockParameters_MIN_WIDTH_SCALE_min() public {
    _runTestCase("test_134_SkewShockParameters_MIN_WIDTH_SCALE_min");
  }

  function test_135_SkewShockParameters_MIN_WIDTH_SCALE_max() public {
    _runTestCase("test_135_SkewShockParameters_MIN_WIDTH_SCALE_max");
  }

  function test_136_SkewShockParameters_VOL_PARAM_1_min() public {
    _runTestCase("test_136_SkewShockParameters_VOL_PARAM_1_min");
  }

  function test_137_SkewShockParameters_VOL_PARAM_1_max() public {
    _runTestCase("test_137_SkewShockParameters_VOL_PARAM_1_max");
  }

  function test_138_SkewShockParameters_VOL_PARAM_2_min() public {
    _runTestCase("test_138_SkewShockParameters_VOL_PARAM_2_min");
  }

  function test_139_SkewShockParameters_VOL_PARAM_2_max() public {
    _runTestCase("test_139_SkewShockParameters_VOL_PARAM_2_max");
  }

  function _runTestCase(string memory testName) internal {
    TEST_NAME = testName;
    REF_TIME = 1630000000;
    JSON = jsonParser.jsonFromRelPath(string.concat(FILE_PATH, "/", testName, ".json"));
    vm.warp(REF_TIME);
    ISubAccounts.AssetBalance[] memory balances = _loadTestData();
    _checkResults(balances);
  }

  function _checkResults(ISubAccounts.AssetBalance[] memory balances) internal {
    PMRM_2.Portfolio memory portfolio = pmrm_2.arrangePortfolioByBalances(balances);

    _logPortfolio(portfolio, REF_TIME);
    _compareResults(portfolio);
  }

  function _compareResults(PMRM_2.Portfolio memory portfolio) internal {
    console.log();
    console.log("===== Other Results =====");

    // CollateralMTM
    int collateralMTM = 0;
    for (uint i = 0; i < portfolio.collaterals.length; i++) {
      collateralMTM += int(portfolio.collaterals[i].value);
    }
    assertApproxEqAbs(collateralMTM, _readBNInt(JSON, ".Result.CollateralMTM"), 1e10, "Collateral MTM");

    int optionMTM = 0;
    for (uint i = 0; i < portfolio.expiries.length; i++) {
      optionMTM += int(portfolio.expiries[i].mtm);
    }

    assertApproxEqRel(optionMTM, _readBNInt(JSON, ".Result.OptionMTM"), 1e10, "Option MTM");

    IPMRM_2.Scenario[] memory scenarios = pmrm_2.getScenarios();

    bool viewOne = true;
    uint scenarioToCheck = 0;

    uint regCount = 0;
    uint tailCount = 0;

    for (uint i = 0; i < scenarios.length; i++) {
      console.log("##### Scenario", i);
      if (scenarios[i].volShock == IPMRM_2.VolShockDirection.None) {
        _logBN("Vol shock: None - Spot shock: ", scenarios[i].spotShock);
      } else if (scenarios[i].volShock == IPMRM_2.VolShockDirection.Up) {
        _logBN("Vol shock: Up - Spot shock: ", scenarios[i].spotShock);
      } else if (scenarios[i].volShock == IPMRM_2.VolShockDirection.Down) {
        _logBN("Vol shock: Down - Spot shock: ", scenarios[i].spotShock);
      } else if (scenarios[i].volShock == IPMRM_2.VolShockDirection.Linear) {
        _logBN("Vol shock: Linear - Spot shock: ", scenarios[i].spotShock);
      } else if (scenarios[i].volShock == IPMRM_2.VolShockDirection.Abs) {
        _logBN("Vol shock: Abs - Spot shock: ", scenarios[i].spotShock);
      } else {
        console.log("Invalid vol shock", uint(scenarios[i].volShock));
        revert("Invalid vol shock");
      }
      _logBN("Dampening factor: ", scenarios[i].dampeningFactor);
      int scenarioMtM = lib.getScenarioPnL(portfolio, scenarios[i]);
      _logBN("Scenario MTM: ", scenarioMtM);

      string memory basePath = string.concat(".Result.reg_losses[", vm.toString(i), "]");
      int scenarioLoss = 0;
      if (JSON.keyExists(basePath)) {
        regCount++;
        scenarioLoss = _readBNInt(JSON, basePath, "[2]");
      } else {
        basePath = string.concat(".Result.tail_losses[", vm.toString(i - regCount), "]");
        if (JSON.keyExists(basePath)) {
          tailCount++;
          scenarioLoss = _readBNInt(JSON, basePath, "[2]");
        } else {
          basePath = string.concat(".Result.skew_losses[", vm.toString(i - tailCount - regCount), "]");
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

    (int mm,,) = pmrm_2.getMarginAndMarkToMarketPub(portfolio, false, scenarios);
    assertApproxEqRel(mm, _readBNInt(JSON, ".Result.MM"), 1e10, "MM");

    (int im,,) = pmrm_2.getMarginAndMarkToMarketPub(portfolio, true, scenarios);
    assertApproxEqRel(im, _readBNInt(JSON, ".Result.IM"), 1e10, "IM");
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

    uint spot = _readBNUint(JSON, ".Scenario.SpotPrice");
    feed.setSpot(spot, _readBNUint(JSON, ".Scenario.SpotConfidence"));

    uint perpSpot = _readBNUint(JSON, ".Scenario.PerpPrice");

    mockPerp.setMockPerpPrice(perpSpot, _readBNUint(JSON, ".Scenario.PerpConfidence"));
    mockPerp.mockAccountPnlAndFunding(
      0, _readBNInt(JSON, ".Scenario.UnrealisedPerpPNL"), _readBNInt(JSON, ".Scenario.UnrealisedFunding")
    );

    console.log("Setting perp spot", perpSpot);
    console.log("perp conf", _readBNUint(JSON, ".Scenario.PerpConfidence"));

    stableFeed.setSpot(_readBNUint(JSON, ".Scenario.StablePrice"), _readBNUint(JSON, ".Scenario.StableConfidence"));

    uint expiryCount = 0;
    while (true) {
      string memory basePath = string.concat(".Scenario.OptionFeeds[", vm.toString(expiryCount), "].");
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

    int cashBal = int(_toBNUint(JSON.readString(string.concat(".Scenario.Cash"))));
    int perpAmt = int(_toBNUint(JSON.readString(string.concat(".Scenario.NumPerps"))));

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
      if (JSON.keyExists(string.concat(".Scenario.Options[", vm.toString(optionCount), "].Expiry")) == false) {
        break;
      }
      optionCount++;
    }

    // Get number of options

    ISubAccounts.AssetBalance[] memory res = new ISubAccounts.AssetBalance[](optionCount);

    // Load each option

    for (uint i = 0; i < optionCount; i++) {
      string memory basePath = string.concat(".Scenario.Options[", vm.toString(i), "].");

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
      if (JSON.keyExists(string.concat(".Scenario.Collaterals[", vm.toString(collatCount), "].Name")) == false) {
        break;
      }
      collatCount++;
    }

    // Get number of collaterals

    ISubAccounts.AssetBalance[] memory res = new ISubAccounts.AssetBalance[](collatCount);

    // Load each collateral

    for (uint i = 0; i < collatCount; i++) {
      string memory basePath = string.concat(".Scenario.Collaterals[", vm.toString(i), "].");

      string memory name = JSON.readString(string.concat(basePath, "Name"));

      IPMRMLib_2.CollateralParameters memory collatParams = IPMRMLib_2.CollateralParameters({
        isEnabled: true,
        isRiskCancelling: JSON.readBool(string.concat(basePath, "IsRiskCancelling")),
        MMHaircut: _readBNUint(JSON, basePath, "MMHaircut"),
        IMHaircut: _readBNUint(JSON, basePath, "IMHaircut")
      });

      MockERC20 erc20 = new MockERC20(name, name);
      WrappedERC20Asset wAsset = new WrappedERC20Asset(subAccounts, erc20);
      MockFeeds newFeed = new MockFeeds();

      assetLabel[address(wAsset)] = name;

      newFeed.setSpot(_readBNUint(JSON, basePath, "Price"), _readBNUint(JSON, basePath, "Confidence"));

      pmrm_2.setCollateralSpotFeed(address(wAsset), newFeed);
      lib.setCollateralParameters(address(wAsset), collatParams);

      uint amount = _toBNUint(JSON.readString(string.concat(basePath, "Amount")));

      res[i] = ISubAccounts.AssetBalance({asset: IAsset(address(wAsset)), subId: 0, balance: int(amount)});
    }

    return res;
  }

  function _setScenarios() internal {
    uint scenariosCount = 0;
    while (true) {
      if (JSON.keyExists(string.concat(".Parameters.Scenarios[", vm.toString(scenariosCount), "]")) == false) {
        break;
      }
      scenariosCount++;
    }

    IPMRM_2.Scenario[] memory scenarios = new IPMRM_2.Scenario[](scenariosCount);
    for (uint i = 0; i < scenariosCount; i++) {
      string memory basePath = string.concat(".Parameters.Scenarios[", vm.toString(i), "].");
      string memory shockDirection = JSON.readString(string.concat(basePath, "VolShockDirection"));
      IPMRM_2.VolShockDirection volShockDirection = IPMRM_2.VolShockDirection.None;
      if (keccak256(abi.encodePacked(shockDirection)) == keccak256(abi.encodePacked("Up"))) {
        volShockDirection = IPMRM_2.VolShockDirection.Up;
      } else if (keccak256(abi.encodePacked(shockDirection)) == keccak256(abi.encodePacked("Down"))) {
        volShockDirection = IPMRM_2.VolShockDirection.Down;
      } else if (keccak256(abi.encodePacked(shockDirection)) == keccak256(abi.encodePacked("LINEAR"))) {
        volShockDirection = IPMRM_2.VolShockDirection.Linear;
      } else if (keccak256(abi.encodePacked(shockDirection)) == keccak256(abi.encodePacked("ABS"))) {
        volShockDirection = IPMRM_2.VolShockDirection.Abs;
      } else if (keccak256(abi.encodePacked(shockDirection)) == keccak256(abi.encodePacked("None"))) {
        volShockDirection = IPMRM_2.VolShockDirection.None;
      } else {
        console.log("Invalid shock direction: ", shockDirection);
        revert("Invalid shock direction");
      }
      scenarios[i] = IPMRM_2.Scenario({
        spotShock: _readBNUint(JSON, basePath, "SpotShock"),
        volShock: volShockDirection,
        dampeningFactor: _readBNUint(JSON, basePath, "DampeningFactor")
      });
    }

    pmrm_2.setScenarios(scenarios);
  }

  function _setLibParams() internal {
    lib.setVolShockParams(
      IPMRMLib_2.VolShockParameters({
        volRangeUp: _readBNUint(JSON, ".Parameters.VolShock.VOLRANGEUP"),
        volRangeDown: _readBNUint(JSON, ".Parameters.VolShock.VOLRANGEDOWN"),
        shortTermPower: _readBNInt(JSON, ".Parameters.VolShock.SHORTTERMPOWER"),
        longTermPower: _readBNInt(JSON, ".Parameters.VolShock.LONGTERMPOWER"),
        dteFloor: _readBNUint(JSON, ".Parameters.VolShock.DTE_FLOOR") * 1 days / 1e18,
        minVolUpShock: _readBNUint(JSON, ".Parameters.VolShock.MIN_VOL_EVAL_SHOCKED")
      })
    );

    lib.setMarginParams(
      IPMRMLib_2.MarginParameters({
        imFactor: _readBNUint(JSON, ".Parameters.Margin.IM_LOSS_FACTOR"),
        mmFactor: _readBNUint(JSON, ".Parameters.Margin.MM_LOSS_FACTOR"),
        shortRateMultScale: _readBNUint(JSON, ".Parameters.Margin.SHORT_RATE_MULTSCALE"),
        longRateMultScale: _readBNUint(JSON, ".Parameters.Margin.LONG_RATE_MULTSCALE"),
        shortRateAddScale: _readBNUint(JSON, ".Parameters.Margin.SHORT_RATE_ADDSCALE"),
        longRateAddScale: _readBNUint(JSON, ".Parameters.Margin.LONG_RATE_ADDSCALE"),
        shortBaseStaticDiscount: _readBNUint(JSON, ".Parameters.Margin.BASE_STATIC_DISCOUNT_NEG"),
        longBaseStaticDiscount: _readBNUint(JSON, ".Parameters.Margin.BASE_STATIC_DISCOUNT")
      })
    );

    lib.setBasisContingencyParams(
      IPMRMLib_2.BasisContingencyParameters({
        scenarioSpotUp: _readBNUint(JSON, ".Parameters.BasisContingency.SCENARIO_SPOT_UP"),
        scenarioSpotDown: _readBNUint(JSON, ".Parameters.BasisContingency.SCENARIO_SPOT_DOWN"),
        basisContAddFactor: _readBNUint(JSON, ".Parameters.BasisContingency.BASIS_CONT_ADD_FACTOR"),
        basisContMultFactor: _readBNUint(JSON, ".Parameters.BasisContingency.BASIS_CONT_MULT_FACTOR")
      })
    );

    lib.setOtherContingencyParams(
      IPMRMLib_2.OtherContingencyParameters({
        pegLossThreshold: _readBNUint(JSON, ".Parameters.OtherContingency.PEG_LOSS_THRESHOLD"),
        pegLossFactor: _readBNUint(JSON, ".Parameters.OtherContingency.PEG_LOSS_FACTOR"),
        confThreshold: _readBNUint(JSON, ".Parameters.OtherContingency.CONF_THRESHOLD"),
        confMargin: _readBNUint(JSON, ".Parameters.OtherContingency.CONF_MARGIN"),
        MMPerpPercent: _readBNUint(JSON, ".Parameters.OtherContingency.MM_PERP_PERCENT"),
        IMPerpPercent: _readBNUint(JSON, ".Parameters.OtherContingency.IM_PERP_PERCENT"),
        MMOptionPercent: _readBNUint(JSON, ".Parameters.OtherContingency.MM_OPTION_PERCENT"),
        IMOptionPercent: _readBNUint(JSON, ".Parameters.OtherContingency.IM_OPTION_PERCENT")
      })
    );

    lib.setSkewShockParameters(
      IPMRMLib_2.SkewShockParameters({
        linearBaseCap: _readBNUint(JSON, ".Parameters.SkewShock.LINEAR_SCALE_CAP"),
        absBaseCap: _readBNUint(JSON, ".Parameters.SkewShock.ABS_SCALE_CAP"),
        linearCBase: _readBNInt(JSON, ".Parameters.SkewShock.LINEAR_CBASE"),
        absCBase: _readBNInt(JSON, ".Parameters.SkewShock.ABS_CBASE"),
        minKStar: _readBNInt(JSON, ".Parameters.SkewShock.MIN_K_STAR"),
        widthScale: _readBNInt(JSON, ".Parameters.SkewShock.MIN_WIDTH_SCALE"),
        volParamStatic: _readBNInt(JSON, ".Parameters.SkewShock.VOL_PARAM_STATIC"),
        volParamScale: _readBNInt(JSON, ".Parameters.SkewShock.VOL_PARAM_SCALE")
      })
    );
  }

  /////////////
  // Helpers //
  /////////////

  function _readBNUint(string memory json, string memory key) internal returns (uint) {
    return _toBNUint(json.readString(key));
  }

  function _readBNUint(string memory json, string memory basePath, string memory key) internal returns (uint) {
    return _toBNUint(json.readString(string.concat(basePath, key)));
  }

  function _readBNInt(string memory json, string memory key) internal returns (int) {
    return _toBNInt(json.readString(key));
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
