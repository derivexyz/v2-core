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

    aliceAcc = createAccountAndDepositDaiLending(alice, 10000000e18);
    bobAcc = createAccountAndDepositDaiLending(bob, 10000000e18);
  }

  function testDeposit() public {
    charlieAcc = createAccountAndDepositDaiLending(charlie, 5000e18);
    // base layer should only reflect pure balance
    assertEq(account.getBalance(charlieAcc, daiLending, 0), 5000e18);

    // asset level fresh balance should also be the same as no borrows
    assertEq(daiLending.getBalance(charlieAcc), 5000e18);
  }

  function testWithdrawal() public {
    daiLending.withdraw(aliceAcc, 10000000e18, charlie);

    // base layer should only reflect pure balance
    assertEq(account.getBalance(aliceAcc, daiLending, 0), 0);

    // asset level fresh balance should also be the same as no borrows
    assertEq(daiLending.getBalance(aliceAcc), 0);

    assertEq(dai.balanceOf(charlie), 10000000e18);
  }

}
