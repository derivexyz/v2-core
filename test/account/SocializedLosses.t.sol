// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../util/LyraHelper.sol";

contract TransferGasTest is Test, LyraHelper {
  address liquidator = vm.addr(5);
  uint aliceAcc;
  uint bobAcc;

  function setUp() public {
    deployPRMSystem();
    setPrices(1e18, 1500e18);

    PortfolioRiskManager.Scenario[] memory scenarios = new PortfolioRiskManager.Scenario[](1);
    scenarios[0] = PortfolioRiskManager.Scenario({spotShock: uint(85e16), ivShock: 10e18});

    setScenarios(scenarios);

    (aliceAcc, bobAcc) = mintAndDepositUSDC(10000000e18, 10000000e18);
  }

  function testSocializedLoss() public {
    setupAssetAllowances(bob, bobAcc, alice);

    // open subId = 0 option
    optionAdapter.addListing(1500e18, block.timestamp + 604800, true);

    // open call w/o premium payment
    vm.startPrank(alice);
    IAccount.AssetTransfer memory optionTransfer = IAccount.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAbstractAsset(optionAdapter),
      subId: 0,
      // TODO: this breaks when amount == totalShortOI
      amount: int(10e18),
      assetData: bytes32(0)
    });

    IAccount.AssetTransfer[] memory transferBatch = new IAccount.AssetTransfer[](1);
    transferBatch[0] = optionTransfer;
    account.submitTransfers(transferBatch, "");
    vm.stopPrank();

    // mock bob being insolvent and losing 1x short
    vm.startPrank(address(rm));
    optionAdapter.socializeLoss(bobAcc, 0, -1e18);
    vm.stopPrank();

    // 

  }

}
