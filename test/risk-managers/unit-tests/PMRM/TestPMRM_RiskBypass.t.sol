pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "../../../../src/risk-managers/PMRM.sol";
import "../../../../src/assets/CashAsset.sol";
import "../../../../src/SubAccounts.sol";
import "../../../../src/interfaces/ISubAccounts.sol";

import "../../../shared/mocks/MockFeeds.sol";
import "../../../shared/mocks/MockFeeds.sol";
import "../../../risk-managers/unit-tests/PMRM/utils/PMRMSimTest.sol";

contract UNIT_TestPMRM_RiskBypass is PMRMSimTest {
  function testPMRMInsufficientMarginRegularTransfer() public {
    ISubAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".BigOne");

    vm.expectRevert(IPMRM.PMRM_InsufficientMargin.selector);
    _doBalanceTransfer(aliceAcc, bobAcc, balances);
  }

  function testPMRMTransferPassesRiskChecks() public {
    ISubAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".BigOne");

    _depositCash(aliceAcc, 200_000 ether);
    _depositCash(bobAcc, 200_000 ether);
    _doBalanceTransfer(aliceAcc, bobAcc, balances);
  }

  function testPMRM_TrustedRiskAssessorBypass() public {
    ISubAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".BigOne");

    // only bob's MTM is negative; alice's MTM is positive but IM is negative - yet trade goes through
    _depositCash(bobAcc, 200_000 ether);

    pmrm.setTrustedRiskAssessor(alice, true);
    vm.startPrank(bob);
    subAccounts.setApprovalForAll(alice, true);
    vm.startPrank(alice);

    _doBalanceTransfer(aliceAcc, bobAcc, balances);
  }

  function testPMRM_TrustedRiskAssessorCanStillRevert() public {
    ISubAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".BigOne");

    // only bob's MTM is negative; alice's MTM is positive but IM is negative - yet trade goes through
    _depositCash(bobAcc, 15_000 ether);
    // for bob:
    // MTM ~ -13k
    // MM(ATM) ~ -16.8k
    // So should revert with only 15k cash
    pmrm.setTrustedRiskAssessor(alice, true);
    vm.startPrank(bob);
    subAccounts.setApprovalForAll(alice, true);
    vm.startPrank(alice);
    vm.expectRevert(IPMRM.PMRM_InsufficientMargin.selector);
    _doBalanceTransfer(aliceAcc, bobAcc, balances);
  }

  function testPMRM_riskReducingTrade() public {
    ISubAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".BigOne");

    _depositCash(aliceAcc, 200_000 ether);
    _depositCash(bobAcc, 150_000 ether);
    _doBalanceTransfer(aliceAcc, bobAcc, balances);

    // Bob IM: ~130k
    feed.setSpot(2000 ether, 1e18);
    // Bob IM: ~168k
    int imPre = pmrm.getMargin(bobAcc, true);

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
    int imPost = pmrm.getMargin(bobAcc, true);
    assertLt(imPre, imPost);
  }

  function testPMRM_riskReducingTradeBasisContingency() public {
    _depositCash(bobAcc, 150_000 ether);

    ISubAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".BasisContingency");
    setBalances(aliceAcc, balances);

    pmrm.setTrustedRiskAssessor(address(this), false);

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
