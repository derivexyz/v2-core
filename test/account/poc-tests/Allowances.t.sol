// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../../util/LyraHelper.sol";

contract TestAllowances is Test, LyraHelper {
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

    // expect revert when alice try to sub bob's usdc
    vm.startPrank(alice);
    vm.expectRevert(
      abi.encodeWithSelector(Allowances.NotEnoughSubIdOrAssetAllowances.selector,
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

  function testCannotTransferWithPartialAllowance() public {    
    uint subId = optionAdapter.addListing(1500e18, block.timestamp + 604800, true);

    vm.startPrank(bob);
    AccountStructs.AssetAllowance[] memory assetAllowances = new AccountStructs.AssetAllowance[](1);
    assetAllowances[0] = AccountStructs.AssetAllowance({
      asset: IAsset(usdcAdapter),
      positive: 0,
      negative: 50e18
    });
    account.setAssetAllowances(bobAcc, alice, assetAllowances);

    AccountStructs.SubIdAllowance[] memory subIdAllowances = new AccountStructs.SubIdAllowance[](1);
    
    subIdAllowances[0] = AccountStructs.SubIdAllowance({
      asset: IAsset(usdcAdapter),
      subId: 0,
      positive: 0,
      negative: 40e18
    });
    account.setSubIdAllowances(bobAcc, alice, subIdAllowances);
    vm.stopPrank();

    // expect revert
    vm.startPrank(alice);
    vm.expectRevert(
      abi.encodeWithSelector(Allowances.NotEnoughSubIdOrAssetAllowances.selector,
        address(account), 
        alice,
        bobAcc,
        -100e18,
        40e18,
        50e18
      )
    );
    tradeOptionWithUSDC(aliceAcc, bobAcc, 1e18, 100e18, subId);
    vm.stopPrank();
  }

  function testCanTradeWithoutAllowanceToIncreaseIfAssetAllows() public {    
    uint subId = optionAdapter.addListing(1500e18, block.timestamp + 604800, true);

    vm.startPrank(bob);
    AccountStructs.AssetAllowance[] memory assetAllowances = new AccountStructs.AssetAllowance[](1);
    assetAllowances[0] = AccountStructs.AssetAllowance({
      asset: IAsset(usdcAdapter),
      positive: 0,
      negative: type(uint).max
    });
    account.setAssetAllowances(bobAcc, alice, assetAllowances);
    vm.stopPrank();

    // expect revert
    vm.startPrank(alice);
    vm.expectRevert(
      abi.encodeWithSelector(Allowances.NotEnoughSubIdOrAssetAllowances.selector,
        address(account), 
        alice,
        bobAcc,
        1000000000000000000,
        0,
        0
      )
    );
    tradeOptionWithUSDC(aliceAcc, bobAcc, 1e18, 100e18, subId);
    vm.stopPrank();
  }

  function testSuccessfulDecrementOfAllowance() public {    
    uint subId = optionAdapter.addListing(1500e18, block.timestamp + 604800, true);

    vm.startPrank(bob);
    AccountStructs.AssetAllowance[] memory assetAllowances = new AccountStructs.AssetAllowance[](1);
    assetAllowances[0] = AccountStructs.AssetAllowance({
      asset: IAsset(usdcAdapter),
      positive: 0,
      negative: 50e18
    });
    account.setAssetAllowances(bobAcc, alice, assetAllowances);

    AccountStructs.SubIdAllowance[] memory subIdAllowances = new AccountStructs.SubIdAllowance[](1);
    subIdAllowances[0] = AccountStructs.SubIdAllowance({
      asset: IAsset(usdcAdapter),
      subId: 0,
      positive: 0,
      negative: 55e18
    });
    account.setSubIdAllowances(bobAcc, alice, subIdAllowances);
    vm.stopPrank();


    // expect revert
    vm.startPrank(alice);
    tradeOptionWithUSDC(aliceAcc, bobAcc, 1e18, 100e18, subId);
    vm.stopPrank();

    // ensure subid allowance decremented first
    assertEq(account.negativeSubIdAllowance(bobAcc, bob, optionAdapter, 0, alice), 0);
    assertEq(account.negativeAssetAllowance(bobAcc, bob, optionAdapter, alice), 0);

    
    assertEq(account.negativeSubIdAllowance(bobAcc, bob, usdcAdapter, 0, alice), 0);
    assertEq(account.negativeAssetAllowance(bobAcc, bob, usdcAdapter, alice), 5e18);
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

  function testCannotTransferWithoutAllowanceForAll() public {    
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

    // giving wrong subId allowance for option asset
    vm.startPrank(alice);
    AccountStructs.SubIdAllowance[] memory subIdAllowances = new AccountStructs.SubIdAllowance[](2);
    subIdAllowances[0] = AccountStructs.SubIdAllowance({
      asset: IAsset(optionAdapter),
      subId: 1, // wrong subId 
      positive: type(uint).max,
      negative: type(uint).max
    });
    subIdAllowances[1] = AccountStructs.SubIdAllowance({
      asset: IAsset(usdcAdapter),
      subId: 0,
      positive: type(uint).max,
      negative: type(uint).max
    });
    account.setSubIdAllowances(aliceAcc, orderbook, subIdAllowances);
    vm.stopPrank();

    // expect revert
    vm.startPrank(orderbook);
    vm.expectRevert(
      abi.encodeWithSelector(IAllowances.NotEnoughSubIdOrAssetAllowances.selector,address(account), 
        orderbook,
        aliceAcc,
        50000000000000000000,
        0,
        0
      )
    );
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
      abi.encodeWithSelector(Allowances.NotEnoughSubIdOrAssetAllowances.selector,address(account), 
        address(0x2B5AD5c4795c026514f8317c7a215E218DcCD6cF),
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

  function testAutoAllowanceWithNewAccount() public {    
    uint subId = optionAdapter.addListing(1500e18, block.timestamp + 604800, true);

    // new user account with spender allowance
    vm.startPrank(alice);
    address user = vm.addr(100);
    uint userAcc = account.createAccountWithApproval(user, bob, IManager(rm));
    vm.stopPrank();

    // successful trade without allowances
    vm.startPrank(bob);
    tradeOptionWithUSDC(userAcc, bobAcc, 1e18, 100e18, subId);
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