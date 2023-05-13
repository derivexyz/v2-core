pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "src/risk-managers/PMRM.sol";
import "src/assets/CashAsset.sol";
import "src/Accounts.sol";
import "src/interfaces/IManager.sol";
import "src/interfaces/IAsset.sol";
import "src/interfaces/IAccounts.sol";

import "test/shared/mocks/MockManager.sol";
import "test/shared/mocks/MockERC20.sol";
import "test/shared/mocks/MockAsset.sol";
import "test/shared/mocks/MockOption.sol";
import "test/shared/mocks/MockSM.sol";
import "test/shared/mocks/MockFeed.sol";

import "test/risk-managers/mocks/MockDutchAuction.sol";
import "test/shared/utils/JsonMechIO.sol";

import "test/shared/mocks/MockFeeds.sol";
import "src/assets/WrappedERC20Asset.sol";
import "test/shared/mocks/MockPerp.sol";

import "./PMRMTestBase.sol";

import "forge-std/console2.sol";

contract UNIT_TestPMRM is PMRMTestBase {
  ///////////////////////
  // Arrange Portfolio //
  ///////////////////////

  function testPMRM() public {
    //    IAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".SingleBase");
    //    IAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".OracleContingency");
    IAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".StableRate");
    //    IAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".BitOfEverything");
    IPMRM.PMRM_Portfolio memory portfolio = pmrm.arrangePortfolio(balances);
    _logPortfolio(portfolio);
    console2.log("im", pmrm.getMargin(balances, true));
    console2.log("mm", pmrm.getMargin(balances, false));
  }

  function testSinglePerp() public {
    IAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".SinglePerp");
  }
}
