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

import "./PMRMTestBase.sol";

import "forge-std/console2.sol";

contract UNIT_TestPMRM_RiskBypass is PMRMTestBase {
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
    assertLt(imPre, 0);

    // Just find one long call rather than hardcode
    for (uint i = 0; i < balances.length; i++) {
      (uint expiry, uint strike, bool isCall) = OptionEncoding.fromSubId(uint96(balances[i].subId));
      if (balances[i].balance < 0 && isCall) {
        ISubAccounts.AssetBalance[] memory closeShortCall = new ISubAccounts.AssetBalance[](1);
        closeShortCall[0] =
          ISubAccounts.AssetBalance({asset: balances[i].asset, balance: balances[i].balance, subId: balances[i].subId});
        _doBalanceTransfer(bobAcc, aliceAcc, closeShortCall);
        break;
      }
    }
    int imPost = pmrm.getMargin(bobAcc, true);
    assertLt(imPre, imPost);
  }
}
