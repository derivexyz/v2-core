pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "../../../../src/risk-managers/PMRM.sol";
import "../../../../src/assets/CashAsset.sol";
import "../../../../src/SubAccounts.sol";
import "../../../../src/interfaces/IManager.sol";
import "../../../../src/interfaces/IAsset.sol";
import "../../../../src/interfaces/ISubAccounts.sol";

import "../../../shared/mocks/MockManager.sol";
import "../../../shared/mocks/MockERC20.sol";
import "../../../shared/mocks/MockAsset.sol";
import "../../../shared/mocks/MockOption.sol";
import "../../../shared/mocks/MockSM.sol";
import "../../../shared/mocks/MockFeeds.sol";

import "../../../risk-managers/mocks/MockDutchAuction.sol";
import "../../../shared/utils/JsonMechIO.sol";

import "../../../shared/mocks/MockFeeds.sol";
import "../../../../src/assets/WrappedERC20Asset.sol";
import "../../../shared/mocks/MockPerp.sol";

import "../../../risk-managers/unit-tests/PMRM/utils/PMRMSimTest.sol";

import "forge-std/console2.sol";

contract UNIT_TestPMRM_Scenarios is PMRMSimTest {
  //  function testPMRMScenario_BigOne() public {
  //    ISubAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".BigOne");
  //    console2.log("im", pmrm.getMarginByBalances(balances, true));
  //    console2.log("mm", pmrm.getMarginByBalances(balances, false));
  //  }
  //
  //  function testPMRMScenario_SinglePerp() public {
  //    ISubAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".SinglePerp");
  //    console2.log("im", pmrm.getMarginByBalances(balances, true));
  //    console2.log("mm", pmrm.getMarginByBalances(balances, false));
  //  }
  //
  //  function testPMRMScenario_SingleBase() public {
  //    ISubAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".SingleBase");
  //    console2.log("im", pmrm.getMarginByBalances(balances, true));
  //    console2.log("mm", pmrm.getMarginByBalances(balances, false));
  //  }
  //
  //  function testPMRMScenario_BitOfEverything() public {
  //    ISubAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".BitOfEverything");
  //    console2.log("im", pmrm.getMarginByBalances(balances, true));
  //    console2.log("mm", pmrm.getMarginByBalances(balances, false));
  //  }
  //
  //  function testPMRMScenario_OracleContingency() public {
  //    ISubAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".OracleContingency");
  //    console2.log("im", pmrm.getMarginByBalances(balances, true));
  //    console2.log("mm", pmrm.getMarginByBalances(balances, false));
  //  }
  //
  //  function testPMRMScenario_StableRate() public {
  //    ISubAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".StableRate");
  //    console2.log("im", pmrm.getMarginByBalances(balances, true));
  //    console2.log("mm", pmrm.getMarginByBalances(balances, false));
  //  }

  function testAndVerifyPMRMScenario1() public {
    setupTestScenarioAndVerifyResults(".Test1");
  }

  function testAndVerifyPMRMScenario2() public {
    setupTestScenarioAndVerifyResults(".Test2");
  }

  function testAndVerifyPMRMScenario3() public {
    setupTestScenarioAndVerifyResults(".Test3");
  }

  function testAndVerifyPMRMScenario4() public {
    setupTestScenarioAndVerifyResults(".Test4");
  }

  function testAndVerifyPMRMScenario5() public {
    setupTestScenarioAndVerifyResults(".Test5");
  }

  function testAndVerifyPMRMScenario6() public {
    setupTestScenarioAndVerifyResults(".Test6");
  }

  function testAndVerifyPMRMScenario7() public {
    setupTestScenarioAndVerifyResults(".Test7");
  }

  function testAndVerifyPMRMScenario8() public {
    setupTestScenarioAndVerifyResults(".Test8");
  }

  function testAndVerifyPMRMScenario9() public {
    setupTestScenarioAndVerifyResults(".Test9");
  }

  function testAndVerifyPMRMScenario10() public {
    setupTestScenarioAndVerifyResults(".Test10");
  }

  function testAndVerifyPMRMScenario11() public {
    setupTestScenarioAndVerifyResults(".Test11");
  }

  function testAndVerifyPMRMScenario12() public {
    setupTestScenarioAndVerifyResults(".Test12");
  }

  function testAndVerifyPMRMScenario13() public {
    setupTestScenarioAndVerifyResults(".Test13");
  }

  function testAndVerifyPMRMScenario14() public {
    setupTestScenarioAndVerifyResults(".Test14");
  }

  function testAndVerifyPMRMScenario15() public {
    setupTestScenarioAndVerifyResults(".Test15");
  }

  function testAndVerifyPMRMScenario16() public {
    setupTestScenarioAndVerifyResults(".Test16");
  }

  function testAndVerifyPMRMScenario17() public {
    setupTestScenarioAndVerifyResults(".Test17");
  }

  function testAndVerifyPMRMScenario18() public {
    setupTestScenarioAndVerifyResults(".Test18");
  }

  function testAndVerifyPMRMScenario19() public {
    setupTestScenarioAndVerifyResults(".Test19");
  }

  function testAndVerifyPMRMScenario20() public {
    setupTestScenarioAndVerifyResults(".Test20");
  }

  function testAndVerifyPMRMScenario21() public {
    setupTestScenarioAndVerifyResults(".Test21");
  }
}
