// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "./AccountPOCHelper.sol";

contract POC_Allowances is Test, AccountPOCHelper {
  uint aliceAcc;
  uint bobAcc;
  uint charlieAcc;
  uint davidAcc;

  function setUp() public {
    deployPRMSystem();
    setPrices(1e18, 1500e18);

    PortfolioRiskPOCManager.Scenario[] memory scenarios = new PortfolioRiskPOCManager.Scenario[](1);
    scenarios[0] = PortfolioRiskPOCManager.Scenario({spotShock: uint(85e16), ivShock: 10e18});

    setScenarios(scenarios);

    aliceAcc = createAccountAndDepositUSDC(alice, 10000000e18);
    bobAcc = createAccountAndDepositUSDC(bob, 10000000e18);
  }

  function testCanTradeWithAssetAllowance() public {
    uint subId = optionAdapter.addListing(1500e18, block.timestamp + 604800, true);

    vm.startPrank(alice);
    IAllowances.AssetAllowance[] memory assetAllowances = new IAllowances.AssetAllowance[](1);
    assetAllowances[0] =
      IAllowances.AssetAllowance({asset: IAsset(optionAdapter), positive: 0, negative: type(uint).max});
    account.setAssetAllowances(aliceAcc, bob, assetAllowances);
    vm.stopPrank();

    vm.startPrank(bob);
    tradeOptionWithUSDC(aliceAcc, bobAcc, 1e18, 100e18, subId);
    vm.stopPrank();
  }

  function testCanTradeWithSubIdAllowance() public {
    uint subId = optionAdapter.addListing(1500e18, block.timestamp + 604800, true);

    vm.startPrank(alice);
    IAllowances.SubIdAllowance[] memory allowances = new IAllowances.SubIdAllowance[](1);
    allowances[0] =
      IAllowances.SubIdAllowance({asset: IAsset(optionAdapter), subId: subId, positive: 0, negative: type(uint).max});
    account.setSubIdAllowances(aliceAcc, bob, allowances);
    vm.stopPrank();

    vm.startPrank(bob);
    tradeOptionWithUSDC(aliceAcc, bobAcc, 1e18, 100e18, subId);
    vm.stopPrank();
  }

  function testCannotTradeWithWrongSubIdAllowance() public {
    uint subId = optionAdapter.addListing(1500e18, block.timestamp + 604800, true);

    vm.startPrank(alice);
    IAllowances.SubIdAllowance[] memory allowances = new IAllowances.SubIdAllowance[](1);
    allowances[0] = IAllowances.SubIdAllowance({
      asset: IAsset(optionAdapter),
      subId: subId + 1,
      positive: 0,
      negative: type(uint).max
    });
    account.setSubIdAllowances(aliceAcc, bob, allowances);
    vm.stopPrank();

    vm.startPrank(bob);
    vm.expectRevert(
      abi.encodeWithSelector(IAllowances.NotEnoughSubIdOrAssetAllowances.selector, bob, aliceAcc, -1e18, 0, 0)
    );
    tradeOptionWithUSDC(aliceAcc, bobAcc, 1e18, 100e18, subId);
    vm.stopPrank();
  }

  function test3rdPartyAllowance() public {
    uint subId = optionAdapter.addListing(1500e18, block.timestamp + 604800, true);
    address orderbook = charlie;

    // give orderbook allowance over both
    IAllowances.AssetAllowance[] memory assetAllowances = new IAllowances.AssetAllowance[](2);
    assetAllowances[0] =
      IAllowances.AssetAllowance({asset: IAsset(optionAdapter), positive: 0, negative: type(uint).max});
    assetAllowances[1] = IAllowances.AssetAllowance({asset: IAsset(usdcAdapter), positive: 0, negative: type(uint).max});

    vm.startPrank(bob);
    account.setAssetAllowances(bobAcc, orderbook, assetAllowances);
    vm.stopPrank();

    vm.startPrank(alice);
    account.setAssetAllowances(aliceAcc, orderbook, assetAllowances);
    vm.stopPrank();

    // expect revert
    vm.startPrank(orderbook);
    tradeOptionWithUSDC(bobAcc, aliceAcc, 50e18, 1000e18, subId);
    vm.stopPrank();
  }
}
