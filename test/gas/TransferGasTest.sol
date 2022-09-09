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

  /// @dev ~300k total cost
  ///      ~2x 25k manager.handleAdjustments
  ///      ~2x 30k option.handleAdjustments [only 2k overhead per call]
  ///      ~2x 2.5k option.handleAdjustments [only 2k overhead per call]
  ///      so account cost: 185k (mostly fixed)
  ///         ~2x 25k cold SSTORES
  ///         ~2x 1k warm SSTORES
  ///         ~2x 70k add held asset

  function testSingleTransfer() public {
    setupAssetAllowances(bob, bobAcc, alice);
    
    // two-way transfer option
    console2.log("start");
    vm.startPrank(alice);
    AccountStructs.AssetTransfer memory optionTransfer = AccountStructs.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: IAbstractAsset(optionAdapter),
      subId: optionAdapter.listingParamsToSubId(1500e18, 123456, true),
      amount: int(1e18)
    });

    AccountStructs.AssetTransfer memory premiumTransfer = AccountStructs.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAbstractAsset(usdcAdapter),
      subId: 0,
      amount: int(100e18)
    });

    AccountStructs.AssetTransfer[] memory transferBatch = new AccountStructs.AssetTransfer[](2);
    transferBatch[0] = optionTransfer;
    transferBatch[1] = premiumTransfer;

    account.submitTransfers(transferBatch);
    vm.stopPrank();
  }

  /// @dev 100 batched transfers
  function testBulkTransfer() public {
    setupAssetAllowances(bob, bobAcc, alice);
    
    // two-way transfer option
    vm.startPrank(alice);
    AccountStructs.AssetTransfer memory optionTransfer = AccountStructs.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: IAbstractAsset(optionAdapter),
      subId: optionAdapter.listingParamsToSubId(1500e18, 123456, true),
      amount: int(1e18)
    });

    AccountStructs.AssetTransfer memory premiumTransfer = AccountStructs.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAbstractAsset(usdcAdapter),
      subId: 0,
      amount: int(100e18)
    });

    AccountStructs.AssetTransfer[] memory transferBatch = 
      new AccountStructs.AssetTransfer[](100);
    
    for (uint i; i < 50; i++) {
      transferBatch[i * 2] = optionTransfer;
      transferBatch[i * 2 + 1] = premiumTransfer;
    }

    account.submitTransfers(transferBatch);
    vm.stopPrank();
  }

  function testTransferBulkAdditionsAndRemovals() public {
    setupAssetAllowances(bob, bobAcc, alice);
    // setupAssetAllowances(alice, aliceAcc, bob);

    // two-way transfer option
    vm.startPrank(alice);
    AccountStructs.AssetTransfer[] memory initialTransfers =
      composeBulkUniqueTransfers(aliceAcc, bobAcc, int(1e18), 5);
    account.submitTransfers(initialTransfers);  

    AccountStructs.AssetTransfer[] memory finalTransfers =
      composeBulkUniqueTransfers(aliceAcc, bobAcc, -int(1e18), 5);
    account.submitTransfers(finalTransfers);  

    vm.stopPrank();

  }

  function testTransferSingleWithLargeAccount() public {
    setupAssetAllowances(bob, bobAcc, alice);
    // setupAssetAllowances(alice, aliceAcc, bob);

    // two-way transfer option
    vm.startPrank(alice);
    AccountStructs.AssetTransfer[] memory initialTransfers =
      composeBulkUniqueTransfers(aliceAcc, bobAcc, int(1e18), 100);
    account.submitTransfers(initialTransfers);  

    AccountStructs.AssetTransfer[] memory singleTransfer = new AccountStructs.AssetTransfer[](1);
    singleTransfer[0] = AccountStructs.AssetTransfer({
        fromAcc: aliceAcc,
        toAcc: bobAcc,
        asset: IAbstractAsset(optionAdapter),
        subId: optionAdapter.listingParamsToSubId(1000e18, 123456, true),
        amount: 1e17
      });
    account.submitTransfers(singleTransfer);  

    vm.stopPrank();

  }

  function composeBulkUniqueTransfers(
    uint fromAcc, uint toAcc, int amount, uint numOfTransfers
  ) internal view returns (AccountStructs.AssetTransfer[] memory transferBatch) {
    transferBatch = new AccountStructs.AssetTransfer[](numOfTransfers);

    for (uint i; i < numOfTransfers; i++) {
      transferBatch[i] = AccountStructs.AssetTransfer({
        fromAcc: fromAcc,
        toAcc: toAcc,
        asset: IAbstractAsset(optionAdapter),
        subId: optionAdapter.listingParamsToSubId(1000e18 + i * 10, 123456, true),
        amount: amount
      });
    }

    return transferBatch;
  }

  function setupAssetAllowances(address owner, uint ownerAcc, address delegate) internal {
    vm.startPrank(owner);
    IAbstractAsset[] memory assets = new IAbstractAsset[](2);
    assets[0] = IAbstractAsset(optionAdapter);
    assets[1] = IAbstractAsset(usdcAdapter);
    AccountStructs.Allowance[] memory allowances = new AccountStructs.Allowance[](2);
    allowances[0] = AccountStructs.Allowance({positive: type(uint).max, negative: type(uint).max});
    allowances[1] = AccountStructs.Allowance({positive: type(uint).max, negative: type(uint).max});

    account.setAssetDelegateAllowances(ownerAcc, delegate, assets, allowances);
    vm.stopPrank();
  }
}
