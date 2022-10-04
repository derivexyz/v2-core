// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "./AccountPOCHelper.sol";

contract POC_PortfolioRiskManager is Test, AccountPOCHelper {
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

    aliceAcc = createAccountAndDepositUSDC(alice, 10_000_000e18);
    bobAcc = createAccountAndDepositUSDC(bob, 10_000_000e18);
  }

  function testManagerCanLiquidateAccount() public {
    setupMaxAssetAllowancesForAll(bob, bobAcc, alice);
  }

  function testManagerCanBatchSettleAccounts() public {
    setupMaxAssetAllowancesForAll(bob, bobAcc, alice);
  }

  function testManagerCanBlockMigrationFromBadManagers() public {

  }

  function testManagerCanBlockMigrationToBadManagers() public {

  }

}
