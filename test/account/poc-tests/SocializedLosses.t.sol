// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "./AccountPOCHelper.sol";

contract POC_SocializedLosses is Test, AccountPOCHelper {
  uint aliceAcc;
  uint bobAcc;
  uint charlieAcc;
  uint davidAcc;

  function setUp() public {
    vm.label(alice, "alice");
    vm.label(bob, "bob");

    deployPRMSystem();
    setPrices(1e18, 1500e18);

    PortfolioRiskPOCManager.Scenario[] memory scenarios = new PortfolioRiskPOCManager.Scenario[](1);
    scenarios[0] = PortfolioRiskPOCManager.Scenario({spotShock: uint(85e16), ivShock: 10e18});

    setScenarios(scenarios);

    aliceAcc = createAccountAndDepositUSDC(alice, 10000000e18);
    bobAcc = createAccountAndDepositUSDC(bob, 10000000e18);
  }

  function testSocializedLossRatioAdjustment() public {
    setupMaxAssetAllowancesForAll(bob, bobAcc, alice);

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
    uint effectiveRatio = DecimalMath.UNIT * optionAdapter.totalShorts(subId) / optionAdapter.totalLongs(subId);
    assertEq(storedRatio, 9e17);
    assertEq(effectiveRatio, 9e17);
  }

  function testSocializedLossOnLending() public {
    uint expiry = block.timestamp + 604800;
    uint strike = 1500e18;
    uint subId = optionAdapter.addListing(strike, expiry, true);

    // Charlie deposited into lending account (his retirement account!)
    uint depositAmount = 10000e18;
    uint retirementAcc = createAccountAndDepositDaiLending(charlie, depositAmount);

    // Bob created a new account with 800 usdc deposit to trade with Alice
    uint bobUSDCAmount = 800e18;
    uint bobNewAcc = createAccountAndDepositUSDC(bob, bobUSDCAmount);
    setupMaxAssetAllowancesForAll(bob, bobNewAcc, alice);
    vm.prank(alice);
    openCallOption(bobNewAcc, aliceAcc, int(1e18), subId); // open call w/o premium payment

    // simulate settlement: Bob become insolvent
    vm.warp(expiry + 1);
    uint settlementPrice = 3000e18;
    setPrices(1e18, 3000e18);
    setSettlementPrice(expiry);
    AccountStructs.HeldAsset[] memory assets = new AccountStructs.HeldAsset[](1);
    assets[0] = AccountStructs.HeldAsset({asset: IAsset(address(optionAdapter)), subId: uint96(subId)});
    rm.settleAssets(bobNewAcc, assets);

    uint expectedInsolventAmount = settlementPrice - strike - bobUSDCAmount;

    // usdc balance stays the same
    assertEq(account.getBalance(bobNewAcc, usdcAdapter, 0), int(bobUSDCAmount));

    // daiLending balance should reflect the negative pnl
    assertEq(account.getBalance(bobNewAcc, daiLending, 0), -int(settlementPrice - strike));

    // socialise loss on everyone else's lending balance!
    daiLending.socializeLoss(bobNewAcc, expectedInsolventAmount);

    // trigger charlie's retirement account to update balance
    AccountStructs.AssetTransfer memory triggerTx = AccountStructs.AssetTransfer({
      fromAcc: retirementAcc,
      toAcc: aliceAcc,
      asset: IAsset(daiLending),
      subId: 0,
      amount: 0,
      assetData: bytes32(0)
    });
    account.submitTransfer(triggerTx, "");

    // charlie now has less money on his account
    int charlieNewBalance = account.getBalance(retirementAcc, daiLending, 0);

    // charlie is the only one with asset deposited, so all loss is on him :(
    assertEq(uint(charlieNewBalance), depositAmount - expectedInsolventAmount);
  }

  function testTradePostSocializedLoss() public {
    setupMaxAssetAllowancesForAll(bob, bobAcc, alice);

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
    charlieAcc = createAccountAndDepositUSDC(charlie, 1000e18);
    davidAcc = createAccountAndDepositUSDC(david, 1000e18);

    // open 1x new option
    setupMaxAssetAllowancesForAll(david, davidAcc, charlie);
    setupMaxAssetAllowancesForAll(alice, aliceAcc, charlie);

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
    AccountStructs.AssetTransfer memory optionTransfer = AccountStructs.AssetTransfer({
      fromAcc: fromAcc,
      toAcc: toAcc,
      asset: IAsset(optionAdapter),
      subId: subId,
      // TODO: this breaks when amount == totalShortOI
      amount: amount,
      assetData: bytes32(0)
    });
    AccountStructs.AssetTransfer[] memory transferBatch = new AccountStructs.AssetTransfer[](1);
    transferBatch[0] = optionTransfer;
    account.submitTransfers(transferBatch, "");
  }
}
