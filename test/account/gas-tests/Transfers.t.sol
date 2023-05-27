// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../poc-tests/AccountPOCHelper.sol";

/**
 * @dev these tests are expected to underestimate SLOAD and SSTORE cost
 */
contract GAS_Transfers is Test, AccountPOCHelper {
  uint aliceAcc;
  uint bobAcc;

  function setUp() public {
    deployPRMSystem();
    setPrices(1e18, 1500e18);

    PortfolioRiskPOCManager.Scenario[] memory scenarios = new PortfolioRiskPOCManager.Scenario[](1);
    scenarios[0] = PortfolioRiskPOCManager.Scenario({spotShock: uint(85e16), ivShock: 10e18});

    setScenarios(scenarios);

    aliceAcc = createAccountAndDepositUSDC(alice, 10000000e18);
    bobAcc = createAccountAndDepositUSDC(bob, 10000000e18);
  }

  /// @dev - Transfer 2x subIds (e.g. cash and option) between two empty accounts
  ///        - ~50k * 2x * numOfSubIds → ~100k on balance/order SSTORE
  ///        - ~50k * 2x * numOfSubIds → ~100k on heldAsset pushes
  ///        - extras + sharing balances with manager + external calls → ~75k
  ///        - Total: `~275k gas overhead` from accounts + asset / manager checks

  function testSingleTransfer() public {
    setupMaxAssetAllowancesForAll(bob, bobAcc, alice);

    // two-way transfer option
    vm.startPrank(alice);
    ISubAccounts.AssetTransfer memory optionTransfer = ISubAccounts.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: IAsset(optionAdapter),
      subId: optionAdapter.addListing(1500e18, block.timestamp + 604800, true),
      amount: int(1e18),
      assetData: bytes32(0)
    });

    ISubAccounts.AssetTransfer memory premiumTransfer = ISubAccounts.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAsset(usdcAdapter),
      subId: 0,
      amount: int(100e18),
      assetData: bytes32(0)
    });

    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](2);
    transferBatch[0] = optionTransfer;
    transferBatch[1] = premiumTransfer;

    subAccounts.submitTransfers(transferBatch, "");
    vm.stopPrank();
  }

  /// @dev 100 batched transfers
  function testBulkTransfer() public {
    setupMaxAssetAllowancesForAll(bob, bobAcc, alice);

    // two-way transfer option
    vm.startPrank(alice);
    ISubAccounts.AssetTransfer memory optionTransfer = ISubAccounts.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: IAsset(optionAdapter),
      subId: optionAdapter.addListing(1500e18, block.timestamp + 604800, true),
      amount: int(1e18),
      assetData: bytes32(0)
    });

    ISubAccounts.AssetTransfer memory premiumTransfer = ISubAccounts.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAsset(usdcAdapter),
      subId: 0,
      amount: int(100e18),
      assetData: bytes32(0)
    });

    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](100);

    for (uint i; i < 50; i++) {
      transferBatch[i * 2] = optionTransfer;
      transferBatch[i * 2 + 1] = premiumTransfer;
    }

    subAccounts.submitTransfers(transferBatch, "");
    vm.stopPrank();
  }

  function testTransferBulkAdditionsAndRemovals() public {
    setupMaxAssetAllowancesForAll(bob, bobAcc, alice);
    // setupMaxAssetAllowancesForAll(alice, aliceAcc, bob);

    // two-way transfer option
    vm.startPrank(alice);
    ISubAccounts.AssetTransfer[] memory initialTransfers = composeBulkUniqueTransfers(aliceAcc, bobAcc, int(1e18), 5);
    subAccounts.submitTransfers(initialTransfers, "");

    ISubAccounts.AssetTransfer[] memory finalTransfers = composeBulkUniqueTransfers(aliceAcc, bobAcc, -int(1e18), 5);
    subAccounts.submitTransfers(finalTransfers, "");

    vm.stopPrank();
  }

  function testTransferSingleWithLargeAccount() public {
    setupMaxAssetAllowancesForAll(bob, bobAcc, alice);
    // setupMaxAssetAllowancesForAll(alice, aliceAcc, bob);

    // two-way transfer option
    vm.startPrank(alice);
    ISubAccounts.AssetTransfer[] memory initialTransfers = composeBulkUniqueTransfers(aliceAcc, bobAcc, int(1e18), 100);
    subAccounts.submitTransfers(initialTransfers, "");

    ISubAccounts.AssetTransfer[] memory singleTransfer = new ISubAccounts.AssetTransfer[](1);
    singleTransfer[0] = ISubAccounts.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: IAsset(optionAdapter),
      subId: optionAdapter.addListing(1000e18, block.timestamp + 604800, true),
      amount: 1e17,
      assetData: bytes32(0)
    });
    subAccounts.submitTransfers(singleTransfer, "");

    vm.stopPrank();
  }

  function composeBulkUniqueTransfers(uint fromAcc, uint toAcc, int amount, uint numOfTransfers)
    internal
    returns (ISubAccounts.AssetTransfer[] memory transferBatch)
  {
    transferBatch = new ISubAccounts.AssetTransfer[](numOfTransfers);

    for (uint i; i < numOfTransfers; i++) {
      transferBatch[i] = ISubAccounts.AssetTransfer({
        fromAcc: fromAcc,
        toAcc: toAcc,
        asset: IAsset(optionAdapter),
        subId: optionAdapter.addListing(1000e18 + i * 10, block.timestamp + 604800, true),
        amount: amount,
        assetData: bytes32(0)
      });
    }

    return transferBatch;
  }
}
