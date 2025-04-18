// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "../../../../src/risk-managers/PMRM_2.sol";
import "../../../../src/SubAccounts.sol";
import "../../../../src/interfaces/ISubAccounts.sol";

import "../../../shared/mocks/MockFeeds.sol";
import "../../../shared/mocks/MockFeeds.sol";
import "../../../risk-managers/unit-tests/PMRM_2/utils/PMRM_2SimTest.sol";

contract UNIT_TestPMRM_2_RiskBypass is PMRM_2SimTest {
  function testPMRM_2InsufficientMarginRegularTransfer() public {
    ISubAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".BigOne");

    vm.expectRevert(IPMRM_2.PMRM_2_InsufficientMargin.selector);
    _doBalanceTransfer(aliceAcc, bobAcc, balances);
  }

  function testPMRM_2TransferPassesRiskChecks() public {
    ISubAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".BigOne");

    _depositCash(aliceAcc, 200_000 ether);
    _depositCash(bobAcc, 200_000 ether);
    _doBalanceTransfer(aliceAcc, bobAcc, balances);
  }

  function testPMRM_2_TrustedRiskAssessorBypass() public {
    ISubAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".BigOne");

    // only bob's MTM is negative; alice's MTM is positive but IM is negative - yet trade goes through
    _depositCash(bobAcc, 200_000 ether);

    pmrm_2.setTrustedRiskAssessor(alice, true);
    vm.startPrank(bob);
    subAccounts.setApprovalForAll(alice, true);
    vm.startPrank(alice);

    _doBalanceTransfer(aliceAcc, bobAcc, balances);
  }

  function testPMRM_2_TrustedRiskAssessorCanStillRevert() public {
    ISubAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".BigOne");

    // only bob's MTM is negative; alice's MTM is positive but IM is negative - yet trade goes through
    _depositCash(bobAcc, 15_000 ether);
    // for bob:
    // MTM ~ -13k
    // MM(ATM) ~ -16.8k
    // So should revert with only 15k cash
    pmrm_2.setTrustedRiskAssessor(alice, true);
    vm.startPrank(bob);
    subAccounts.setApprovalForAll(alice, true);
    vm.startPrank(alice);
    vm.expectRevert(IPMRM_2.PMRM_2_InsufficientMargin.selector);
    _doBalanceTransfer(aliceAcc, bobAcc, balances);
  }

  function testPMRM_2_riskReducingTrade() public {
    ISubAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".BigOne");

    _depositCash(aliceAcc, 200_000 ether);
    _depositCash(bobAcc, 150_000 ether);
    _doBalanceTransfer(aliceAcc, bobAcc, balances);

    // Bob IM: ~130k
    feed.setSpot(2000 ether, 1e18);
    // Bob IM: ~168k
    int imPre = pmrm_2.getMargin(bobAcc, true);

    // Just find one long call rather than hardcode
    for (uint i = 0; i < balances.length; i++) {
      (,, bool isCall) = OptionEncoding.fromSubId(uint96(balances[i].subId));
      if (balances[i].balance < 0 && isCall) {
        ISubAccounts.AssetBalance[] memory closeShortCall = new ISubAccounts.AssetBalance[](2);
        closeShortCall[0] =
          ISubAccounts.AssetBalance({asset: balances[i].asset, balance: balances[i].balance, subId: balances[i].subId});
        closeShortCall[1] = ISubAccounts.AssetBalance({asset: cash, balance: -0.001e18, subId: 0});
        _doBalanceTransfer(bobAcc, aliceAcc, closeShortCall);
        break;
      }
    }
    int imPost = pmrm_2.getMargin(bobAcc, true);
    assertLt(imPre, imPost);
  }

  function testPMRM_2_riskReducingTradeBasisContingency() public {
    _depositCash(bobAcc, 150_000e18);

    // TODO: double check this test, originally didnt have to add cash to alice
    _depositCash(aliceAcc, 15_000e18);

    ISubAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".BasisContingency");
    setBalances(aliceAcc, balances);

    pmrm_2.setTrustedRiskAssessor(address(this), false);

    for (uint i = 0; i < balances.length; i++) {
      (,, bool isCall) = OptionEncoding.fromSubId(uint96(balances[i].subId));
      if (balances[i].balance < 0 && isCall) {
        ISubAccounts.AssetBalance[] memory closeShortCall = new ISubAccounts.AssetBalance[](2);
        // bob donates 0.001 call to alice
        closeShortCall[0] =
          ISubAccounts.AssetBalance({asset: balances[i].asset, balance: 0.001e18, subId: balances[i].subId});
        closeShortCall[1] = ISubAccounts.AssetBalance({asset: cash, balance: -0.001e18, subId: 0});
        _doBalanceTransfer(bobAcc, aliceAcc, closeShortCall);
        break;
      }
    }
  }
}
