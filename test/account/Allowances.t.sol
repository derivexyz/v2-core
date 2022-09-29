// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../util/LyraHelper.sol";

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

    // expect revert
    vm.startPrank(alice);
    vm.expectRevert(
      abi.encodeWithSelector(IAllowances.NotEnoughSubIdOrAssetAllowances.selector,
        address(0xF2E246BB76DF876Cef8b38ae84130F4F55De395b), 
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

  function testCannotTransferWithPartialAllowance() public {    
    uint subId = optionAdapter.addListing(1500e18, block.timestamp + 604800, true);

    vm.startPrank(bob);
    IAllowances.AssetAllowance[] memory assetAllowances = new IAllowances.AssetAllowance[](2);
    assetAllowances[0] = IAllowances.AssetAllowance({
      asset: IAsset(optionAdapter),
      positive: 5e17,
      negative: 0
    });
    assetAllowances[1] = IAllowances.AssetAllowance({
      asset: IAsset(usdcAdapter),
      positive: 0,
      negative: 50e18
    });
    account.setAssetAllowances(bobAcc, alice, assetAllowances);

    IAllowances.SubIdAllowance[] memory subIdAllowances = new IAllowances.SubIdAllowance[](2);
    subIdAllowances[0] = IAllowances.SubIdAllowance({
      asset: IAsset(optionAdapter),
      subId: 0,
      positive: 4e17,
      negative: 0
    });
    subIdAllowances[1] = IAllowances.SubIdAllowance({
      asset: IAsset(usdcAdapter),
      subId: 0,
      positive: 0,
      negative: 50e18
    });
    account.setSubIdAllowances(bobAcc, alice, subIdAllowances);
    vm.stopPrank();

    // expect revert
    vm.startPrank(alice);
    vm.expectRevert(
      abi.encodeWithSelector(IAllowances.NotEnoughSubIdOrAssetAllowances.selector,
        address(0xF2E246BB76DF876Cef8b38ae84130F4F55De395b), 
        alice,
        bobAcc,
        1000000000000000000,
        400000000000000000,
        500000000000000000
      )
    );
    tradeOptionWithUSDC(aliceAcc, bobAcc, 1e18, 100e18, subId);
    vm.stopPrank();
  }

  function testNotEnoughAllowance() public {    
    uint subId = optionAdapter.addListing(1500e18, block.timestamp + 604800, true);

    vm.startPrank(bob);
    IAllowances.AssetAllowance[] memory assetAllowances = new IAllowances.AssetAllowance[](1);
    assetAllowances[0] = IAllowances.AssetAllowance({
      asset: IAsset(usdcAdapter),
      positive: type(uint).max,
      negative: type(uint).max
    });
    account.setAssetAllowances(bobAcc, alice, assetAllowances);
    vm.stopPrank();

    // expect revert
    vm.startPrank(alice);
    vm.expectRevert(
      abi.encodeWithSelector(IAllowances.NotEnoughSubIdOrAssetAllowances.selector,
        address(0xF2E246BB76DF876Cef8b38ae84130F4F55De395b), 
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
    IAllowances.AssetAllowance[] memory assetAllowances = new IAllowances.AssetAllowance[](2);
    assetAllowances[0] = IAllowances.AssetAllowance({
      asset: IAsset(optionAdapter),
      positive: 5e17,
      negative: 0
    });
    assetAllowances[1] = IAllowances.AssetAllowance({
      asset: IAsset(usdcAdapter),
      positive: 0,
      negative: 50e18
    });
    account.setAssetAllowances(bobAcc, alice, assetAllowances);

    IAllowances.SubIdAllowance[] memory subIdAllowances = new IAllowances.SubIdAllowance[](2);
    subIdAllowances[0] = IAllowances.SubIdAllowance({
      asset: IAsset(optionAdapter),
      subId: 0,
      positive: 8e17,
      negative: 0
    });
    subIdAllowances[1] = IAllowances.SubIdAllowance({
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
    assertEq(account.positiveSubIdAllowance(bobAcc, bob, optionAdapter, 0, alice), 0);
    assertEq(account.negativeSubIdAllowance(bobAcc, bob, optionAdapter, 0, alice), 0);
    assertEq(account.positiveAssetAllowance(bobAcc, bob, optionAdapter, alice), 3e17);
    assertEq(account.negativeAssetAllowance(bobAcc, bob, optionAdapter, alice), 0);

    assertEq(account.positiveSubIdAllowance(bobAcc, bob, usdcAdapter, 0, alice), 0);
    assertEq(account.negativeSubIdAllowance(bobAcc, bob, usdcAdapter, 0, alice), 0);
    assertEq(account.positiveAssetAllowance(bobAcc, bob, usdcAdapter, alice), 0);
    assertEq(account.negativeAssetAllowance(bobAcc, bob, usdcAdapter, alice), 5e18);
  }

  function test3rdPartyAllowance() public {    
    uint subId = optionAdapter.addListing(1500e18, block.timestamp + 604800, true);
    address orderbook = charlie;

    // give orderbook allowance over both
    IAllowances.AssetAllowance[] memory assetAllowances = new IAllowances.AssetAllowance[](2);
    assetAllowances[0] = IAllowances.AssetAllowance({
      asset: IAsset(optionAdapter),
      positive: type(uint).max,
      negative: type(uint).max
    });
    assetAllowances[1] = IAllowances.AssetAllowance({
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
    IAllowances.AssetAllowance[] memory assetAllowances = new IAllowances.AssetAllowance[](2);
    assetAllowances[0] = IAllowances.AssetAllowance({
      asset: IAsset(optionAdapter),
      positive: type(uint).max,
      negative: type(uint).max
    });
    assetAllowances[1] = IAllowances.AssetAllowance({
      asset: IAsset(usdcAdapter),
      positive: type(uint).max,
      negative: type(uint).max
    });

    vm.startPrank(bob);
    account.setAssetAllowances(bobAcc, orderbook, assetAllowances);
    vm.stopPrank();

    // giving wrong subId allowance for option asset
    vm.startPrank(alice);
    IAllowances.SubIdAllowance[] memory subIdAllowances = new IAllowances.SubIdAllowance[](2);
    subIdAllowances[0] = IAllowances.SubIdAllowance({
      asset: IAsset(optionAdapter),
      subId: 1, // wrong subId 
      positive: type(uint).max,
      negative: type(uint).max
    });
    subIdAllowances[1] = IAllowances.SubIdAllowance({
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
      abi.encodeWithSelector(IAllowances.NotEnoughSubIdOrAssetAllowances.selector,
        address(0xF2E246BB76DF876Cef8b38ae84130F4F55De395b), 
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
      abi.encodeWithSelector(IAllowances.NotEnoughSubIdOrAssetAllowances.selector,
        address(0xF2E246BB76DF876Cef8b38ae84130F4F55De395b), 
        address(0x2B5AD5c4795c026514f8317c7a215E218DcCD6cF),
        bobNewAcc,
        1000000000000000000,
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
    uint userAcc = account.createAccount(user, bob, IManager(rm));
    vm.stopPrank();

    // successful trade without allowances
    vm.startPrank(bob);
    tradeOptionWithUSDC(userAcc, bobAcc, 1e18, 100e18, subId);
    vm.stopPrank();
  }

  function tradeOptionWithUSDC(
    uint fromAcc, uint toAcc, uint optionAmount, uint usdcAmount, uint optionSubId
  ) internal {
    IAccount.AssetTransfer memory optionTransfer = IAccount.AssetTransfer({
      fromAcc: fromAcc,
      toAcc: toAcc,
      asset: IAsset(optionAdapter),
      subId: optionSubId,
      amount: int(optionAmount),
      assetData: bytes32(0)
    });

    IAccount.AssetTransfer memory premiumTransfer = IAccount.AssetTransfer({
      fromAcc: toAcc,
      toAcc: fromAcc,
      asset: IAsset(usdcAdapter),
      subId: 0,
      amount: int(usdcAmount),
      assetData: bytes32(0)
    });

    IAccount.AssetTransfer[] memory transferBatch = new IAccount.AssetTransfer[](2);
    transferBatch[0] = optionTransfer;
    transferBatch[1] = premiumTransfer;

    account.submitTransfers(transferBatch, "");
  }
}