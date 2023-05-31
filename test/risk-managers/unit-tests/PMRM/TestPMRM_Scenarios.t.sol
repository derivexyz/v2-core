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

import "test/risk-managers/mocks/MockDutchAuction.sol";
import "test/shared/utils/JsonMechIO.sol";

import "test/shared/mocks/MockFeeds.sol";
import "src/assets/WrappedERC20Asset.sol";
import "test/shared/mocks/MockPerp.sol";

import "test/risk-managers/unit-tests/PMRM/utils/PMRMSimTest.sol";

import "forge-std/console2.sol";

contract UNIT_TestPMRM_Scenarios is PMRMSimTest {
  function testPMRMScenario_BigOne() public {
    ISubAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".BigOne");
    console2.log("im", pmrm.getMarginByBalances(balances, true));
    console2.log("mm", pmrm.getMarginByBalances(balances, false));
  }

  function testPMRMScenario_SinglePerp() public {
    ISubAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".SinglePerp");
    console2.log("im", pmrm.getMarginByBalances(balances, true));
    console2.log("mm", pmrm.getMarginByBalances(balances, false));
  }

  function testPMRMScenario_SingleBase() public {
    ISubAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".SingleBase");
    console2.log("im", pmrm.getMarginByBalances(balances, true));
    console2.log("mm", pmrm.getMarginByBalances(balances, false));
  }

  function testPMRMScenario_BitOfEverything() public {
    ISubAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".BitOfEverything");
    console2.log("im", pmrm.getMarginByBalances(balances, true));
    console2.log("mm", pmrm.getMarginByBalances(balances, false));
  }

  function testPMRMScenario_OracleContingency() public {
    ISubAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".OracleContingency");
    console2.log("im", pmrm.getMarginByBalances(balances, true));
    console2.log("mm", pmrm.getMarginByBalances(balances, false));
  }

  function testPMRMScenario_StableRate() public {
    ISubAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".StableRate");
    console2.log("im", pmrm.getMarginByBalances(balances, true));
    console2.log("mm", pmrm.getMarginByBalances(balances, false));
  }
}
