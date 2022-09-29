// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../../util/LyraHelper.sol";

contract POC_Allowances is Test, LyraHelper {
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

    aliceAcc = createAccountAndDepositUSDC(alice, 10000000e18);
    bobAcc = createAccountAndDepositUSDC(bob, 10000000e18);
  }

  function testCannotTransferWithoutAllowance() public {    
    uint subId = optionAdapter.addListing(1500e18, block.timestamp + 604800, true);
<<<<<<< HEAD

    // expect revert when alice try to sub bob's usdc
    vm.startPrank(alice);
    vm.expectRevert(
      abi.encodeWithSelector(Allowances.NotEnoughSubIdOrAssetAllowances.selector,
=======
    // expect revert
    vm.startPrank(alice);
    vm.expectRevert(
      abi.encodeWithSelector(IAllowances.NotEnoughSubIdOrAssetAllowances.selector,
>>>>>>> 809f024 (fix: tests)
        address(account), 
        alice,
        bobAcc,
        -100e18,
        0,
        0
      )
    );
    tradeOptionWithUSDC(aliceAcc, bobAcc, 1e18, 100e18, subId);
    vm.stopPrank();
  }

  function test3rdPartyAllowance() public {    
    uint subId = optionAdapter.addListing(1500e18, block.timestamp + 604800, true);
    address orderbook = charlie;

    // give orderbook allowance over both
    AccountStructs.AssetAllowance[] memory assetAllowances = new AccountStructs.AssetAllowance[](2);
    assetAllowances[0] = AccountStructs.AssetAllowance({
      asset: IAsset(optionAdapter),
      positive: type(uint).max,
      negative: type(uint).max
    });
    assetAllowances[1] = AccountStructs.AssetAllowance({
      asset: IAsset(usdcAdapter),
      positive: type(uint).max,
      negative: type(uint).max
    });

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

  function testERC721Approval() public {    
    uint subId = optionAdapter.addListing(1500e18, block.timestamp + 604800, true);

    vm.startPrank(bob);
    account.approve(alice, bobAcc);
    vm.stopPrank();

    // successful trade
    vm.startPrank(alice);
    tradeOptionWithUSDC(aliceAcc, bobAcc, 1e18, 100e18, subId);
    vm.stopPrank();

    // revert with new account
    uint bobNewAcc = createAccountAndDepositUSDC(bob, 10000000e18);
    vm.startPrank(alice);
    vm.expectRevert(
      abi.encodeWithSelector(Allowances.NotEnoughSubIdOrAssetAllowances.selector,
        address(account),
        address(alice),
        bobNewAcc,
        -100e18,
        0,
        0
      )
    );
    tradeOptionWithUSDC(aliceAcc, bobNewAcc, 1e18, 100e18, subId);
    vm.stopPrank();
  }

  function testERC721ApprovalForAll() public {    
    uint subId = optionAdapter.addListing(1500e18, block.timestamp + 604800, true);

    vm.startPrank(bob);
    account.setApprovalForAll(alice, true);
    vm.stopPrank();

    // successful trade
    vm.startPrank(alice);
    tradeOptionWithUSDC(aliceAcc, bobAcc, 1e18, 100e18, subId);
    vm.stopPrank();

    // successful trade even with new account from same user
    uint bobNewAcc = createAccountAndDepositUSDC(bob, 10000000e18);
    vm.startPrank(alice);
    tradeOptionWithUSDC(aliceAcc, bobNewAcc, 1e18, 100e18, subId);
    vm.stopPrank();
  }

  function testManagerInitiatedTransfer() public {    
    uint subId = optionAdapter.addListing(1500e18, block.timestamp + 604800, true);

    // successful trade without allowances
    vm.startPrank(address(rm));
    tradeOptionWithUSDC(aliceAcc, bobAcc, 1e18, 100e18, subId);
    vm.stopPrank();
  }

  function tradeOptionWithUSDC(
    uint fromAcc, uint toAcc, uint optionAmount, uint usdcAmount, uint optionSubId
  ) internal {
    AccountStructs.AssetTransfer memory optionTransfer = AccountStructs.AssetTransfer({
      fromAcc: fromAcc,
      toAcc: toAcc,
      asset: IAsset(optionAdapter),
      subId: optionSubId,
      amount: int(optionAmount),
      assetData: bytes32(0)
    });

    AccountStructs.AssetTransfer memory premiumTransfer = AccountStructs.AssetTransfer({
      fromAcc: toAcc,
      toAcc: fromAcc,
      asset: IAsset(usdcAdapter),
      subId: 0,
      amount: int(usdcAmount),
      assetData: bytes32(0)
    });

    AccountStructs.AssetTransfer[] memory transferBatch = new AccountStructs.AssetTransfer[](2);
    transferBatch[0] = optionTransfer;
    transferBatch[1] = premiumTransfer;

    account.submitTransfers(transferBatch, "");
  }
}