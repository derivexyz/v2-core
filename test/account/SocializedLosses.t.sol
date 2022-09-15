// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../util/LyraHelper.sol";

contract SocializedLosses is Test, LyraHelper {
  uint aliceAcc;
  uint bobAcc;
  uint charlieAcc;
  uint davidAcc;


  function setUp() public {
    deployPRMSystem();
    setPrices(1e18, 1500e18);

    PortfolioRiskManager.Scenario[] memory scenarios = new PortfolioRiskManager.Scenario[](1);
    scenarios[0] = PortfolioRiskManager.Scenario({spotShock: uint(85e16), ivShock: 10e18});

    setScenarios(scenarios);

    aliceAcc = createAccountAndDepositUSDC(alice, 10000000e18);
    bobAcc = createAccountAndDepositUSDC(bob, 10000000e18);
  }

  function testSocializedLossRatioAdjustment() public {
    setupAssetAllowances(bob, bobAcc, alice);

    // open subId = 0 option
    uint subId = optionAdapter.addListing(1500e18, block.timestamp + 604800, true);

    // open call w/o premium payment
    vm.startPrank(alice);
    openCallOption(bobAcc, aliceAcc, int(10e18), subId);
    vm.stopPrank();

    // mock bob being insolvent and losing 1x short
    vm.startPrank(address(rm));
    optionAdapter.socializeLoss(bobAcc, subId, 1e18);
    vm.stopPrank();

    // new ratio should be 0.9
    uint storedRatio = optionAdapter.ratios(subId);
    uint effectiveRatio = 
      DecimalMath.UNIT * optionAdapter.totalShorts(subId) / optionAdapter.totalLongs(subId);
    assertEq(storedRatio, 9e17);
    assertEq(effectiveRatio, 9e17);
  }

  function testTradePostSocializedLoss() public {
    setupAssetAllowances(bob, bobAcc, alice);

    // 10% socialized loss
    optionAdapter.addListing(1500e18, block.timestamp + 604800, true);
    uint subId = 0;
    vm.startPrank(alice);
    openCallOption(bobAcc, aliceAcc, int(10e18), subId);
    vm.stopPrank();
    vm.startPrank(address(rm));
    optionAdapter.socializeLoss(bobAcc, subId, 1e18); // 10% loss
    vm.stopPrank();

    // trade post loss
    vm.startPrank(charlie);
    charlieAcc = account.createAccount(charlie, IAbstractManager(rm));
    vm.stopPrank();
    vm.startPrank(david);
    davidAcc = account.createAccount(david, IAbstractManager(rm));
    vm.stopPrank();

    // open 1x new option
    setupAssetAllowances(david, davidAcc, charlie);
    setupAssetAllowances(alice, aliceAcc, charlie);
    vm.startPrank(charlie);
    openCallOption(charlieAcc, davidAcc, 1e18, 0);
    vm.stopPrank();

    // make sure balance of david is actually 1.1
    assertEq(account.getBalance(davidAcc, optionAdapter, 0), 1111111111111111111);

    // do sign change -> charlie goes from -1 -> 2
    vm.startPrank(charlie);
    openCallOption(aliceAcc, charlieAcc, 2e18, 0);
    vm.stopPrank();

    // make sure new balance of bob is decremented by more than 2
    assertEq(account.getBalance(aliceAcc, optionAdapter, 0), 7777777777777777778);
  }

  function openCallOption(uint fromAcc, uint toAcc, int amount, uint subId) public {
    IAccount.AssetTransfer memory optionTransfer = IAccount.AssetTransfer({
      fromAcc: fromAcc,
      toAcc: toAcc,
      asset: IAbstractAsset(optionAdapter),
      subId: subId,
      // TODO: this breaks when amount == totalShortOI
      amount: amount,
      assetData: bytes32(0)
    });
    IAccount.AssetTransfer[] memory transferBatch = new IAccount.AssetTransfer[](1);
    transferBatch[0] = optionTransfer;
    account.submitTransfers(transferBatch, "");
  }

}
