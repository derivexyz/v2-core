// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "./AccountPOCHelper.sol";

contract POC_PortfolioRiskManager is Test, AccountPOCHelper {
  uint aliceAcc;
  uint bobAcc;
  uint charlieAcc;
  uint davidAcc;

  // fake option property
  uint strike;
  uint expiry;
  uint subId;
  address orderbook = address(0xb00c);

  function setUp() public {
    vm.label(alice, "alice");
    vm.label(bob, "bob");

    deployPRMSystem();
    setPrices(1e18, 1500e18);

    PortfolioRiskPOCManager.Scenario[] memory scenarios = new PortfolioRiskPOCManager.Scenario[](1);
    scenarios[0] = PortfolioRiskPOCManager.Scenario({spotShock: uint(85e16), ivShock: 10e18});

    setScenarios(scenarios);

    aliceAcc = createAccountAndDepositUSDC(alice, 1000e18);
    bobAcc = createAccountAndDepositUSDC(bob, 10_000e18);

    // allow trades
    setupMaxAssetAllowancesForAll(bob, bobAcc, orderbook);
    setupMaxAssetAllowancesForAll(alice, aliceAcc, orderbook);

    // stimulate trade
    expiry = block.timestamp + 604800;
    strike = 1500e18;
    subId = optionAdapter.addListing(strike, expiry, true);
    vm.startPrank(orderbook);

    // alice short call, bob long call
    tradeOptionWithUSDC(aliceAcc, bobAcc, 1e18, 100e18, subId);
    vm.stopPrank();
  }

  function testManagerCanLiquidateAccount() public {
    setPrices(1e18, 2500e18);
    rm.flagLiquidation(aliceAcc);

    int aliceUSDCBefore = subAccounts.getBalance(aliceAcc, usdcAdapter, 0);
    int bobUSDCBefore = subAccounts.getBalance(bobAcc, usdcAdapter, 0);

    vm.startPrank(bob);
    int extraCollat = 500e18;
    rm.liquidateAccount(aliceAcc, bobAcc, extraCollat); // add some usdc and get the account
    vm.stopPrank();

    // account is now bob's
    assertEq(subAccounts.ownerOf(aliceAcc), bob);

    assertEq(subAccounts.getBalance(aliceAcc, usdcAdapter, 0), aliceUSDCBefore + extraCollat);
    assertEq(subAccounts.getBalance(bobAcc, usdcAdapter, 0), bobUSDCBefore - extraCollat);
  }

  function testManagerCanBatchSettleAccounts() public {
    // set settlement price: option expires itm
    int cashValue = 100e18;
    setPrices(1e18, strike + uint(cashValue));
    vm.warp(expiry + 1);
    setSettlementPrice(expiry);

    // settlment
    ISubAccounts.HeldAsset[] memory assets = new ISubAccounts.HeldAsset[](1);
    assets[0] = ISubAccounts.HeldAsset({asset: IAsset(address(optionAdapter)), subId: uint96(subId)});
    rm.settleAssets(aliceAcc, assets);
    rm.settleAssets(bobAcc, assets);

    // check settlement values are reflected in daiLending balance
    assertEq(subAccounts.getBalance(aliceAcc, daiLending, 0), -cashValue);
    assertEq(subAccounts.getBalance(bobAcc, daiLending, 0), cashValue);
  }

  function testManagerCanBlockMigrationToBadManagers() public {
    address manager = address(0xbeef);
    vm.expectRevert("wrong manager");
    vm.prank(alice);
    subAccounts.changeManager(aliceAcc, IManager(manager), "");
  }
}
