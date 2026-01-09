// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "../../../../src/risk-managers/PMRMLib_2.sol";

import "../../../risk-managers/unit-tests/PMRM_2/utils/PMRM_2SimTest.sol";

import "./utils/PMRM_2_1Public.sol";

contract TestPMRM_2_1_Upgrade is PMRM_2SimTest {
  function setUp() public override {
    super.setUp();
  }

  function deployNewLib() internal returns (PMRMLib_2) {
    PMRMLib_2 newLib = new PMRMLib_2();

    // Copy defaults, then tweak just one parameter to guarantee a different margin.
    (
      IPMRMLib_2.BasisContingencyParameters memory basisContParams,
      IPMRMLib_2.OtherContingencyParameters memory otherContParams,
      IPMRMLib_2.MarginParameters memory marginParams,
      IPMRMLib_2.VolShockParameters memory volShockParams,
      IPMRMLib_2.SkewShockParameters memory skewShockParams
    ) = Config.getPMRM_2Params();

    // Make MM meaningfully different
    marginParams.mmFactor = marginParams.mmFactor - 0.2e18;

    newLib.setBasisContingencyParams(basisContParams);
    newLib.setOtherContingencyParams(otherContParams);
    newLib.setMarginParams(marginParams);
    newLib.setVolShockParams(volShockParams);
    newLib.setSkewShockParameters(skewShockParams);

    // also ensure collateral parameters align (base asset is enabled in the original lib)
    newLib.setCollateralParameters(
      address(baseAsset),
      IPMRMLib_2.CollateralParameters({isEnabled: true, isRiskCancelling: true, MMHaircut: 0.02e18, IMHaircut: 0.01e18})
    );

    return newLib;
  }

  function testUpgradePreservesAccountsAndDifferentLibParamsChangeMargin() public {
    // 1) Create two NEW accounts before upgrading (in addition to aliceAcc/bobAcc)
    //    This makes it explicit we have user state created pre-upgrade.
    uint accA = subAccounts.createAccount(alice, IManager(address(pmrm_2)));
    uint accB = subAccounts.createAccount(bob, IManager(address(pmrm_2)));

    // Verify state exists pre-upgrade
    assertEq(subAccounts.ownerOf(accA), alice);
    assertEq(subAccounts.ownerOf(accB), bob);

    // 2) Set up a risky portfolio on accA that has a meaningful non-zero margin requirement
    //    We’ll use the same JSON driven fixtures used across PMRM_2 tests.
    //    Fund first to avoid risk-check reverts when we set balances.
    _depositCash(accA, 200_000e18);

    // Use a scenario that includes options/perp and is sensitive to margin params
    // (".BigOne" is used in other tests to trigger insufficient margin).
    ISubAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".BigOne");
    setBalances(accA, balances);

    int mmOld = pmrm_2.getMargin(accA, false);
    // sanity: should be non-zero for the test to be meaningful
    assertTrue(mmOld != 0);

    // 3) Upgrade proxy to PMRM_2_1 implementation (public harness so setBalances remains callable)
    PMRM_2_1Public newImp = new PMRM_2_1Public();
    proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(pmrm_2)), address(newImp), new bytes(0));

    // Rebind to the upgraded type
    PMRM_2_1Public pmrmUpgraded = PMRM_2_1Public(address(pmrm_2));
    // 4) Ensure account state is still there post-upgrade
    assertEq(subAccounts.ownerOf(accA), alice);
    assertEq(subAccounts.ownerOf(accB), bob);

    // Margin should be unchanged if using the same underlying lib
    int mmAfterUpgradeSameLib = pmrmUpgraded.getMargin(accA, false);
    assertEq(mmAfterUpgradeSameLib, mmOld);

    // 5) Deploy a new lib with DIFFERENT parameters, whitelist it for accA,
    //    and show the margin requirement changes.
    PMRMLib_2 newLib = deployNewLib();
    pmrmUpgraded.setWlLib(accA, IPMRMLib_2(address(newLib)));

    int mmNewLib = pmrmUpgraded.getMargin(accA, false);

    // The key assertion for this test: different lib params => different margin requirement
    assertTrue(mmNewLib != mmOld);
    assertTrue(mmNewLib > mmOld);
    // For completeness, account without whitelist still uses the old lib.
    // Set the same balances on accB and show it matches old behavior.
    _depositCash(accB, 200_000e18);
    setBalances(accB, balances);
    int mmAccB = pmrmUpgraded.getMargin(accB, false);
    assertEq(mmAccB, mmOld);
  }

  function testLiquidationMaxLiquidatableAndResetParams() public {
    PMRM_2_1Public newImp = new PMRM_2_1Public();
    proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(pmrm_2)), address(newImp), new bytes(0));
    PMRM_2_1Public pmrmUpgraded = PMRM_2_1Public(address(pmrm_2));
    PMRMLib_2 newLib = deployNewLib();

    uint acc = subAccounts.createAccount(alice, IManager(address(pmrmUpgraded)));
    assertEq(subAccounts.ownerOf(acc), alice);

    ISubAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".BigOne");
    setBalances(acc, balances);
    pmrmUpgraded.setWlLib(acc, IPMRMLib_2(address(newLib)));

    (int mm, int mtm, uint worstScenario) = pmrmUpgraded.getMarginAndMtM(acc, false);

    int cashBalance = subAccounts.getBalance(acc, cash, 0);

    ISubAccounts.AssetBalance[] memory cashWithdrawal = new ISubAccounts.AssetBalance[](1);
    // Set cash balance to mm - 1 to ensure underwater after withdrawal.
    cashWithdrawal[0] = ISubAccounts.AssetBalance({asset: cash, subId: 0, balance: cashBalance - mm - 1e18});
    setBalances(acc, cashWithdrawal);

    (mm, mtm, worstScenario) = pmrmUpgraded.getMarginAndMtM(acc, false);

    assertTrue(mm < 0);
    assertTrue(mtm > 0);

    // Start liquidation auction (should succeed because account is below MM).
    auction.startAuction(acc, worstScenario);
    assertTrue(auction.isAuctionLive(acc));

    // --- Added assertions for WL vs non-WL max proportion ---
    // While WL lib is active, max liquidatable proportion should be more conservative.
    uint maxPropWl = auction.getMaxProportion(acc, worstScenario);
    assertTrue(maxPropWl > 0);
    assertTrue(maxPropWl <= 1e18);

    // Remove from WL (permissionless once the account is in liquidation)
    vm.prank(alice);
    pmrmUpgraded.removeFromWL(acc);
    assertEq(address(pmrmUpgraded.getAccountLib(acc)), address(lib));

    uint maxPropNoWl = auction.getMaxProportion(acc, worstScenario);
    assertTrue(maxPropNoWl > 0);
    assertTrue(maxPropNoWl <= 1e18);

    // Removing WL should increase max proportion (less strict default lib).
    assertTrue(maxPropNoWl > maxPropWl);
  }

  function testOnlyOwnerCanSetWlButGuardianCanRemove() public {
    PMRM_2_1Public newImp = new PMRM_2_1Public();
    proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(pmrm_2)), address(newImp), new bytes(0));
    PMRM_2_1Public pmrmUpgraded = PMRM_2_1Public(address(pmrm_2));
    PMRMLib_2 newLib = deployNewLib();

    uint acc = subAccounts.createAccount(alice, IManager(address(pmrmUpgraded)));
    assertEq(subAccounts.ownerOf(acc), alice);

    pmrm_2.setGuardian(bob);

    // Non-owner/guardian cannot set WL lib
    vm.prank(bob);
    vm.expectRevert(PMRM_2_1.PM21_OnlyOwnerOrGuardian.selector);
    pmrmUpgraded.setWlLib(acc, IPMRMLib_2(address(newLib)));

    // Owner can set WL lib
    vm.prank(address(this));
    pmrmUpgraded.setWlLib(acc, IPMRMLib_2(address(newLib)));
    assertEq(address(pmrmUpgraded.getAccountLib(acc)), address(newLib));


    vm.expectRevert(PMRM_2_1.PM21_AccountNotInLiquidation.selector);
    pmrmUpgraded.removeFromWL(acc);

    // Non-owner/non-guardian cannot remove from WL
    vm.prank(alice);
    vm.expectRevert(PMRM_2_1.PM21_OnlyOwnerOrGuardian.selector);
    pmrmUpgraded.setWlLib(acc, IPMRMLib_2(address(0)));

    // Guardian can remove from WL
    vm.prank(bob);
    pmrmUpgraded.setWlLib(acc, IPMRMLib_2(address(0)));
    // Resets to default lib
    assertEq(address(pmrmUpgraded.getAccountLib(acc)), address(lib));
  }
}
