// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../util/LyraHelper.sol";

contract LoanTest is Test, LyraHelper {
  address liquidator = vm.addr(5);

  function setUp() public {
    deployPRMSystem();
    setPrices(1e18, 1500e18);

    PortfolioRiskManager.Scenario[] memory scenarios = new PortfolioRiskManager.Scenario[](1);
    scenarios[0] = PortfolioRiskManager.Scenario({spotShock: uint(85e16), ivShock: 10e18});

    setScenarios(scenarios);
  }

  function testLoan() public {
    uint ALICE_BAL = 120000e18;
    uint BOB_BAL = 100e18;

    vm.startPrank(alice);
    uint lenderAcc = account.createAccount(IAbstractManager(rm), alice);
    vm.stopPrank();
    vm.startPrank(bob);
    uint depositorAcc = account.createAccount(IAbstractManager(rm), bob);
    vm.stopPrank();
    vm.startPrank(charlie);
    uint drawerAcc = account.createAccount(IAbstractManager(rm), charlie);
    vm.stopPrank();

    assertEq(lenderAcc, 1);
    assertEq(depositorAcc, 2);
    assertEq(drawerAcc, 3);

    vm.startPrank(owner);
    usdc.mint(alice, ALICE_BAL);
    weth.mint(bob, BOB_BAL);
    vm.stopPrank();

    vm.startPrank(alice);
    usdc.approve(address(usdcAdapter), type(uint).max);
    usdcAdapter.deposit(lenderAcc, ALICE_BAL);
    vm.stopPrank();

    vm.startPrank(bob);
    weth.approve(address(wethAdapter), type(uint).max);
    wethAdapter.deposit(depositorAcc, BOB_BAL);
    vm.stopPrank();

    // Move eth from depositor to drawer account
    assertTrue(true);
    account.submitTransfer(
      AccountStructs.AssetTransfer({
        fromAcc: depositorAcc,
        toAcc: drawerAcc,
        asset: IAbstractAsset(wethAdapter),
        subId: 0,
        amount: int(BOB_BAL)
      })
    );

    // Cannot liquidate
    vm.startPrank(liquidator);
    vm.expectRevert(bytes("cannot be liquidated"));
    rm.flagLiquidation(drawerAcc);
    vm.stopPrank();

    // Take out a loan against ETH
    vm.startPrank(charlie);
    usdcAdapter.withdraw(drawerAcc, ALICE_BAL, charlie);
    // Cant withdraw more than all the quote in the system
    vm.expectRevert(bytes("ERC20: transfer amount exceeds balance"));
    usdcAdapter.withdraw(drawerAcc, 1e18, charlie);
    vm.stopPrank();

    setPrices(1e18, 1200e18);

    vm.startPrank(charlie);
    // Also cant take on too much debt
    vm.expectRevert(bytes("Too much debt"));
    usdcAdapter.withdraw(drawerAcc, 1e18, charlie);
    vm.stopPrank();

    vm.startPrank(liquidator);
    rm.flagLiquidation(drawerAcc);
    vm.stopPrank();
  }
}
