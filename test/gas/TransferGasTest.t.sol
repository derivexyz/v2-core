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

  /// @dev ~100k + manager / option hooks per transfer
  ///      ~2x manager.handleAdjustments [2k overhead per external call]
  ///      ~2x option.handleAdjustments [2k overhead per external call]
  ///      account cost: 50k (mostly fixed)
  ///         ~2x balanceAndOrder SSTORE: 20k
  ///         ~2x heldAsset.push(): 20k
  ///         ~2x getAccountBalances: 2k

  function testSingleTransfer() public {
    setupAssetAllowances(bob, bobAcc, alice);
    
    // two-way transfer option
    vm.startPrank(alice);
    IAccount.AssetTransfer memory optionTransfer = IAccount.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: IAbstractAsset(optionAdapter),
      subId: optionAdapter.addListing(1500e18, block.timestamp + 604800, true),
      amount: int(1e18),
      assetData: bytes32(0)
    });

    IAccount.AssetTransfer memory premiumTransfer = IAccount.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAbstractAsset(usdcAdapter),
      subId: 0,
      amount: int(100e18),
      assetData: bytes32(0)
    });

    IAccount.AssetTransfer[] memory transferBatch = new IAccount.AssetTransfer[](2);
    transferBatch[0] = optionTransfer;
    transferBatch[1] = premiumTransfer;

    account.submitTransfers(transferBatch, "");
    vm.stopPrank();
  }

  /// @dev 100 batched transfers
  function testBulkTransfer() public {
    setupAssetAllowances(bob, bobAcc, alice);
    
    // two-way transfer option
    vm.startPrank(alice);
    IAccount.AssetTransfer memory optionTransfer = IAccount.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: IAbstractAsset(optionAdapter),
      subId: optionAdapter.addListing(1500e18, block.timestamp + 604800, true),
      amount: int(1e18),
      assetData: bytes32(0)
    });

    IAccount.AssetTransfer memory premiumTransfer = IAccount.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAbstractAsset(usdcAdapter),
      subId: 0,
      amount: int(100e18),
      assetData: bytes32(0)
    });

    IAccount.AssetTransfer[] memory transferBatch = 
      new IAccount.AssetTransfer[](100);
    
    for (uint i; i < 50; i++) {
      transferBatch[i * 2] = optionTransfer;
      transferBatch[i * 2 + 1] = premiumTransfer;
    }

    account.submitTransfers(transferBatch, "");
    vm.stopPrank();
  }

  function testTransferBulkAdditionsAndRemovals() public {
    setupAssetAllowances(bob, bobAcc, alice);
    // setupAssetAllowances(alice, aliceAcc, bob);

    // two-way transfer option
    vm.startPrank(alice);
    IAccount.AssetTransfer[] memory initialTransfers =
      composeBulkUniqueTransfers(aliceAcc, bobAcc, int(1e18), 5);
    account.submitTransfers(initialTransfers, "");  

    IAccount.AssetTransfer[] memory finalTransfers =
      composeBulkUniqueTransfers(aliceAcc, bobAcc, -int(1e18), 5);
    account.submitTransfers(finalTransfers, "");  

    vm.stopPrank();

  }

  function testTransferSingleWithLargeAccount() public {
    setupAssetAllowances(bob, bobAcc, alice);
    // setupAssetAllowances(alice, aliceAcc, bob);

    // two-way transfer option
    vm.startPrank(alice);
    IAccount.AssetTransfer[] memory initialTransfers =
      composeBulkUniqueTransfers(aliceAcc, bobAcc, int(1e18), 100);
    account.submitTransfers(initialTransfers, "");  

    IAccount.AssetTransfer[] memory singleTransfer = new IAccount.AssetTransfer[](1);
    singleTransfer[0] = IAccount.AssetTransfer({
        fromAcc: aliceAcc,
        toAcc: bobAcc,
        asset: IAbstractAsset(optionAdapter),
        subId: optionAdapter.addListing(1000e18, block.timestamp + 604800, true),
        amount: 1e17,
        assetData: bytes32(0)
      });
    account.submitTransfers(singleTransfer, "");  

    vm.stopPrank();

  }

  function composeBulkUniqueTransfers(
    uint fromAcc, uint toAcc, int amount, uint numOfTransfers
  ) internal returns (IAccount.AssetTransfer[] memory transferBatch) {
    transferBatch = new IAccount.AssetTransfer[](numOfTransfers);

    for (uint i; i < numOfTransfers; i++) {
      transferBatch[i] = IAccount.AssetTransfer({
        fromAcc: fromAcc,
        toAcc: toAcc,
        asset: IAbstractAsset(optionAdapter),
        subId: optionAdapter.addListing(1000e18 + i * 10, block.timestamp + 604800, true),
        amount: amount,
        assetData: bytes32(0)
      });
    }

    return transferBatch;
  }
}
