// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../util/LyraHelper.sol";

// TODO: forge treats storage slots as WARM for all tests within a contract
//       may need to use hardhat or cast

contract Transfers is Test, LyraHelper {
  address liquidator = vm.addr(5);
  uint aliceAcc;
  uint bobAcc;

  function setUp() public {
    deployPRMSystem();
    setPrices(1e18, 1500e18);

    PortfolioRiskManager.Scenario[] memory scenarios = new PortfolioRiskManager.Scenario[](1);
    scenarios[0] = PortfolioRiskManager.Scenario({spotShock: uint(85e16), ivShock: 10e18});

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
    setupAssetAllowances(bob, bobAcc, alice);
    
    // two-way transfer option
    vm.startPrank(alice);
    IAccount.AssetTransfer memory optionTransfer = IAccount.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: IAsset(optionAdapter),
      subId: optionAdapter.addListing(1500e18, block.timestamp + 604800, true),
      amount: int(1e18),
      assetData: bytes32(0)
    });

    IAccount.AssetTransfer memory premiumTransfer = IAccount.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAsset(usdcAdapter),
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
      asset: IAsset(optionAdapter),
      subId: optionAdapter.addListing(1500e18, block.timestamp + 604800, true),
      amount: int(1e18),
      assetData: bytes32(0)
    });

    IAccount.AssetTransfer memory premiumTransfer = IAccount.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAsset(usdcAdapter),
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
        asset: IAsset(optionAdapter),
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
        asset: IAsset(optionAdapter),
        subId: optionAdapter.addListing(1000e18 + i * 10, block.timestamp + 604800, true),
        amount: amount,
        assetData: bytes32(0)
      });
    }

    return transferBatch;
  }
}
