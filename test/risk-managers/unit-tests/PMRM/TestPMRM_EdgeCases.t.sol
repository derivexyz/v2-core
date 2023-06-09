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

contract UNIT_TestPMRM_EdgeCases is PMRMSimTest {
  function testPMRM_perpTransfer() public {
    ISubAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".SinglePerp");

    _depositCash(aliceAcc, 2_000 ether);
    _depositCash(bobAcc, 2_000 ether);
    _doBalanceTransfer(aliceAcc, bobAcc, balances);
  }

  function testPMRM_unsupportedAsset() public {
    MockOption newAsset = new MockOption(subAccounts);
    // newAsset.setWhitelistManager(address(pmrm), true);

    ISubAccounts.AssetBalance[] memory balances = new ISubAccounts.AssetBalance[](1);
    balances[0] = ISubAccounts.AssetBalance({asset: IAsset(address(newAsset)), balance: 1_000 ether, subId: 0});
    vm.expectRevert(IPMRM.PMRM_UnsupportedAsset.selector);
    _doBalanceTransfer(aliceAcc, bobAcc, balances);
  }

  function testPMRM_merge() public {
    ISubAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".SinglePerp");

    _depositCash(aliceAcc, 2_000 ether);
    _depositCash(bobAcc, 2_000 ether);
    _doBalanceTransfer(aliceAcc, bobAcc, balances);

    uint[] memory mergeAccs = new uint[](1);
    mergeAccs[0] = bobAcc;

    // Fails when not owned by the same user
    vm.prank(alice);
    vm.expectRevert(IBaseManager.BM_MergeOwnerMismatch.selector);
    pmrm.mergeAccounts(aliceAcc, mergeAccs);

    // So then transfer alice's account to bob
    vm.prank(alice);
    subAccounts.transferFrom(alice, bob, aliceAcc);

    // and now they can merge!
    vm.prank(bob);
    pmrm.mergeAccounts(aliceAcc, mergeAccs);

    // perps cancel out, leaving bob with double the cash!
    ISubAccounts.AssetBalance[] memory bals = subAccounts.getAccountBalances(aliceAcc);
    assertEq(bals.length, 1);
    assertEq(bals[0].balance, 4_000 ether);
    assertEq(address(bals[0].asset), address(cash));
  }

  function testPMRM_invalidSpotShock() public {
    IPMRM.Scenario[] memory scenarios = new IPMRM.Scenario[](1);
    scenarios[0] = IPMRM.Scenario({spotShock: 3e18 + 1, volShock: IPMRM.VolShockDirection.None});

    vm.expectRevert(IPMRM.PMRM_InvalidSpotShock.selector);
    pmrm.setScenarios(scenarios);

    // but this works fine
    scenarios[0].spotShock = 3e18;
    pmrm.setScenarios(scenarios);
  }

  function testPMRM_notFoundError() public {
    IPMRM.ExpiryHoldings[] memory expiryData = new IPMRM.ExpiryHoldings[](0);
    vm.expectRevert(IPMRM.PMRM_FindInArrayError.selector);
    pmrm.findInArrayPub(expiryData, 0, 0);
  }

  function testPMRM_invalidGetMarginState() public {
    IPMRM.Scenario[] memory scenarios = new IPMRM.Scenario[](0);

    IPMRM.Portfolio memory portfolio;
    vm.expectRevert(IPMRMLib.PMRML_InvalidGetMarginState.selector);
    pmrm.getMarginAndMarkToMarketPub(portfolio, true, scenarios, false);

    (int margin, int mtm, uint worstScenario) = pmrm.getMarginAndMarkToMarketPub(portfolio, true, scenarios, true);
    assertEq(margin, 0);
    assertEq(mtm, 0);
    // since there are no scenarios, worstScenario is the basisContingency
    assertEq(worstScenario, 0);
  }
}
