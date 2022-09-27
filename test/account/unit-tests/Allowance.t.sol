// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../../../src/interfaces/IAccount.sol";

import {AccountTestBase} from "./AccountTestBase.sol";

contract Unit_Allowances is Test, AccountTestBase {
  
  function setUp() public {
    setUpAccounts();
  }

  function testCannotTransferWithoutAllowance() public {    
    // expect revert
    vm.startPrank(alice);
    vm.expectRevert(
      abi.encodeWithSelector(IAccount.NotEnoughSubIdOrAssetAllowances.selector, 
        address(account), 
        alice,
        bobAcc,
        10e18,
        0,
        0
      )
    );
    tradeTokens(aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), 10e18, 10e18, 0, 0);
    vm.stopPrank();
  }

  function testTransferWithEnoughAssetAllowance() public {
    uint tradeAmount = 1e18;
    uint subId = 10000;

    vm.startPrank(bob);
    // bob allow alice to move its cool token, agree to receive USDC
    IAccount.AssetAllowance[] memory assetAllowances = new IAccount.AssetAllowance[](2);
    assetAllowances[0] = IAccount.AssetAllowance({
      asset: coolAsset,
      positive: 0,
      negative: tradeAmount
    });
    assetAllowances[1] = IAccount.AssetAllowance({
      asset: usdcAsset,
      positive: tradeAmount,
      negative: 0
    });
    account.setAssetAllowances(bobAcc, alice, assetAllowances);
    vm.stopPrank();

    // alice trade USDC in echange of Bob's coolToken
    vm.startPrank(alice);
    tradeTokens(aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), tradeAmount, tradeAmount, 0, subId);
    vm.stopPrank();

    // test end state
    uint256 usdcAllowanceLeft = account.positiveAssetAllowance(bobAcc, bob, usdcAsset, alice);
    uint256 tokenAllowanceLeft = account.negativeAssetAllowance(bobAcc, bob, coolAsset, alice);
    assertEq(usdcAllowanceLeft, 0);
    assertEq(tokenAllowanceLeft, 0);
  }

  function testTransferWithEnoughSubIdAllowance() public {
    uint tradeAmount = 1e18;
    uint subId = 10000;

    vm.startPrank(bob);
    // bob allow alice to move its cool token, agree to receive USDC
    IAccount.SubIdAllowance[] memory subIdAllowances = new IAccount.SubIdAllowance[](2);
    subIdAllowances[0] = IAccount.SubIdAllowance({
      asset: coolAsset,
      subId: subId,
      positive: 0,
      negative: tradeAmount
    });
    subIdAllowances[1] = IAccount.SubIdAllowance({
      asset: usdcAsset,
      subId: 0,
      positive: tradeAmount,
      negative: 0
    });
    account.setSubIdAllowances(bobAcc, alice, subIdAllowances);
    vm.stopPrank();

    // alice trade USDC in echange of Bob's coolToken
    vm.startPrank(alice);
    tradeTokens(aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), 1e18, 1e18, 0, subId);
    vm.stopPrank();

    // test end state
    uint256 usdcAllowanceLeft = account.positiveSubIdAllowance(bobAcc, bob, usdcAsset, 0, alice);
    uint256 tokenAllowanceLeft = account.negativeSubIdAllowance(bobAcc, bob, coolAsset, subId, alice);
    assertEq(usdcAllowanceLeft, 0);
    assertEq(tokenAllowanceLeft, 0);
  }

  function testTransferWithEnoughTotalAllowance() public {
    uint tradeAmount = 1e18;
    uint subId = 10000;

    vm.startPrank(bob);
    // bob allow alice to move its cool token, agree to receive USDC
    IAccount.AssetAllowance[] memory assetAllowances = new IAccount.AssetAllowance[](2);
    assetAllowances[0] = IAccount.AssetAllowance({
      asset: coolAsset,
      positive: 0,
      negative: tradeAmount / 2
    });
    assetAllowances[1] = IAccount.AssetAllowance({
      asset: usdcAsset,
      positive: tradeAmount / 2,
      negative: 0
    });
    account.setAssetAllowances(bobAcc, alice, assetAllowances);

    IAccount.SubIdAllowance[] memory subIdAllowances = new IAccount.SubIdAllowance[](2);
    subIdAllowances[0] = IAccount.SubIdAllowance({
      asset: coolAsset,
      subId: subId,
      positive: 0,
      negative: tradeAmount / 2
    });
    subIdAllowances[1] = IAccount.SubIdAllowance({
      asset: usdcAsset,
      subId: 0,
      positive: tradeAmount / 2,
      negative: 0
    });
    account.setSubIdAllowances(bobAcc, alice, subIdAllowances);
    vm.stopPrank();

    // alice trade USDC in echange of Bob's coolToken
    vm.startPrank(alice);
    tradeTokens(aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), tradeAmount, tradeAmount, 0, subId);
    vm.stopPrank();

    // all allowance are spent now
    assertEq(account.positiveSubIdAllowance(bobAcc, bob, usdcAsset, 0, alice), 0);
    assertEq(account.negativeSubIdAllowance(bobAcc, bob, coolAsset, subId, alice), 0);
    assertEq(account.positiveAssetAllowance(bobAcc, bob, usdcAsset, alice), 0);
    assertEq(account.negativeAssetAllowance(bobAcc, bob, coolAsset, alice), 0);
  }

  function testCannotTransferWithPartialNegativeAllowance() public {    
    uint subId = 10000;

    vm.startPrank(bob);
    // bob allow alice to move its cool token, agree to receive USDC
    IAccount.AssetAllowance[] memory assetAllowances = new IAccount.AssetAllowance[](2);
    assetAllowances[0] = IAccount.AssetAllowance({
      asset: coolAsset,
      positive: 0,
      negative: 5e17
    });
    assetAllowances[1] = IAccount.AssetAllowance({
      asset: usdcAsset,
      positive: 1e18,
      negative: 0
    });
    account.setAssetAllowances(bobAcc, alice, assetAllowances);

    IAccount.SubIdAllowance[] memory subIdAllowances = new IAccount.SubIdAllowance[](2);
    subIdAllowances[0] = IAccount.SubIdAllowance({
      asset: coolAsset,
      subId: subId,
      positive: 0,
      negative: 4e17
    });
    subIdAllowances[1] = IAccount.SubIdAllowance({
      asset: usdcAsset,
      subId: 0,
      positive: 1e18,
      negative: 0
    });
    account.setSubIdAllowances(bobAcc, alice, subIdAllowances);
    vm.stopPrank();

    // expect revert
    vm.startPrank(alice);
    vm.expectRevert(
      abi.encodeWithSelector(IAccount.NotEnoughSubIdOrAssetAllowances.selector, 
        address(account), 
        alice,
        bobAcc,
        -1e18,
        4e17, // subId allowance
        5e17  // asset allowance
      )
    );

    // alice trade USDC in echange of Bob's coolToken
    tradeTokens(aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), 1e18, 1e18, 0, subId);
    vm.stopPrank();
  }

  function testCannotTransferWithInsufficientPositiveAllowance() public {    
    // trade will revert if receiver doesn't specify allowance to increase its position
    uint subId = 10000;
    uint tradeAmount = 1e18;

    vm.startPrank(bob);
    // bob allow alice to move its cool token
    IAccount.AssetAllowance[] memory assetAllowances = new IAccount.AssetAllowance[](1);
    assetAllowances[0] = IAccount.AssetAllowance({
      asset: coolAsset,
      positive: 0,
      negative: tradeAmount
    });
    account.setAssetAllowances(bobAcc, alice, assetAllowances);
    vm.stopPrank();

    // expect revert
    vm.startPrank(alice);
    vm.expectRevert(
      abi.encodeWithSelector(IAccount.NotEnoughSubIdOrAssetAllowances.selector, 
        address(account), 
        alice,
        bobAcc,
        tradeAmount, // cannot increase amount!
        0, // subId allowance
        0  // asset allowance
      )
    );

    // alice trade USDC in echange of Bob's coolToken
    tradeTokens(aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), tradeAmount, tradeAmount, 0, subId);
    vm.stopPrank();
  }

  function test3rdPartyAllowance() public {    
    uint subId = 1000;
    address orderbook = address(0xb00c);

    // give orderbook allowance over both
    IAccount.AssetAllowance[] memory assetAllowances = new IAccount.AssetAllowance[](2);
    assetAllowances[0] = IAccount.AssetAllowance({
      asset: coolAsset,
      positive: type(uint).max,
      negative: type(uint).max
    });
    assetAllowances[1] = IAccount.AssetAllowance({
      asset: usdcAsset,
      positive: type(uint).max,
      negative: type(uint).max
    });

    vm.startPrank(bob);
    account.setAssetAllowances(bobAcc, orderbook, assetAllowances);
    vm.stopPrank();

    vm.startPrank(alice);
    account.setAssetAllowances(aliceAcc, orderbook, assetAllowances);
    vm.stopPrank();

    vm.startPrank(orderbook);
    tradeTokens(aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), 1e18, 2e18, 0, subId);
    vm.stopPrank();
  }

  function testCannotTransferBy3rdPartyWithoutAllowance() public {    
    uint subId = 1000;
    address orderbook = address(0xb00c);

    // bob give orderbook allowance over both
    IAccount.AssetAllowance[] memory assetAllowances = new IAccount.AssetAllowance[](2);
    assetAllowances[0] = IAccount.AssetAllowance({
      asset: coolAsset,
      positive: type(uint).max,
      negative: type(uint).max
    });
    assetAllowances[1] = IAccount.AssetAllowance({
      asset: usdcAsset,
      positive: type(uint).max,
      negative: type(uint).max
    });

    vm.startPrank(bob);
    account.setAssetAllowances(bobAcc, orderbook, assetAllowances);
    vm.stopPrank();

    // alice gives wrong subId allowance for tokenAsset asset
    vm.startPrank(alice);
    IAccount.SubIdAllowance[] memory subIdAllowances = new IAccount.SubIdAllowance[](2);
    subIdAllowances[0] = IAccount.SubIdAllowance({
      asset: coolAsset,
      subId: subId + 1, // wrong subId 
      positive: type(uint).max,
      negative: type(uint).max
    });
    subIdAllowances[1] = IAccount.SubIdAllowance({
      asset: usdcAsset,
      subId: 0,
      positive: type(uint).max,
      negative: type(uint).max
    });
    account.setSubIdAllowances(aliceAcc, orderbook, subIdAllowances);
    vm.stopPrank();

    // expect revert
    vm.startPrank(orderbook);
    vm.expectRevert(
      abi.encodeWithSelector(IAccount.NotEnoughSubIdOrAssetAllowances.selector, 
        address(account), 
        orderbook,
        aliceAcc,
        5e17,
        0,
        0
      )
    );
    tradeTokens(aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), 1e18, 5e17, 0, subId);
    vm.stopPrank();
  }

  function testERC721Approval() public {    
    uint subId = 1000;
    uint tradeAmount = 1e18;
    
    vm.startPrank(bob);
    account.approve(alice, bobAcc);
    vm.stopPrank();

    // successful trade
    vm.startPrank(alice);
    tradeTokens(aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), tradeAmount, tradeAmount, 0, subId);
    vm.stopPrank();
  }

  function testERC721ApprovalForAll() public {    
    uint subId = 1000;
    uint tradeAmount = 1e18;

    vm.startPrank(bob);
    account.setApprovalForAll(alice, true);
    vm.stopPrank();

    // successful trade
    vm.startPrank(alice);
    tradeTokens(aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), tradeAmount, tradeAmount, 0, subId);
    vm.stopPrank();

    // successful trade even with new account from same user
    uint bobNewAcc = account.createAccount(bob, dumbManager);
    mintAndDeposit(
      bob,
      bobAcc,
      coolToken,
      coolAsset,
      tradeAmount
    );    

    vm.startPrank(alice);
    tradeTokens(aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), tradeAmount, tradeAmount, 0, subId);
    vm.stopPrank();
  }

  // function testManagerInitiatedTransfer() public {    
  //   // successful trade without allowances
  //   vm.startPrank(address(rm));
  //   tradeOptionWithUSDC(aliceAcc, bobAcc, 1e18, 100e18, subId);
  //   vm.stopPrank();
  // }

  // function testAutoAllowanceWithNewAccount() public {    
  //   uint subId = coolAsset.addListing(1500e18, block.timestamp + 604800, true);

  //   // new user account with spender allowance
  //   vm.startPrank(alice);
  //   address user = vm.addr(100);
  //   uint userAcc = account.createAccount(user, bob, IManager(rm));
  //   vm.stopPrank();

  //   // successful trade without allowances
  //   vm.startPrank(bob);
  //   tradeOptionWithUSDC(userAcc, bobAcc, 1e18, 100e18, subId);
  //   vm.stopPrank();
  // }

  
}