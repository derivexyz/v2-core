// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../../../src/interfaces/IAccount.sol";
import "../../../src/interfaces/IAllowances.sol";

import {AccountTestBase} from "./AccountTestBase.sol";

contract UNIT_Allowances is Test, AccountTestBase {
  
  function setUp() public {
    setUpAccounts();
  }

  function testCannotTransferWithoutPositiveAllowance() public {
    int256 amount = 1e18;
    vm.startPrank(alice);
    vm.expectRevert(
      abi.encodeWithSelector(IAllowances.NotEnoughSubIdOrAssetAllowances.selector, 
        address(account), 
        alice,
        bobAcc,
        amount,
        0,
        0
      )
    );
    transferToken(aliceAcc, bobAcc, usdcAsset, 0, amount);
    vm.stopPrank();
  }

  function testCannotTradeWithoutAllowance() public {    
    // expect revert
    vm.startPrank(alice);
    vm.expectRevert(
      abi.encodeWithSelector(IAllowances.NotEnoughSubIdOrAssetAllowances.selector, 
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

  function testTradeWithEnoughAssetAllowance() public {
    uint tradeAmount = 1e18;

    vm.startPrank(bob);
    // bob allow alice to move its cool token, agree to receive USDC
    AccountStructs.AssetAllowance[] memory assetAllowances = new AccountStructs.AssetAllowance[](2);
    assetAllowances[0] = AccountStructs.AssetAllowance({
      asset: coolAsset,
      positive: 0,
      negative: tradeAmount
    });
    assetAllowances[1] = AccountStructs.AssetAllowance({
      asset: usdcAsset,
      positive: tradeAmount,
      negative: 0
    });
    account.setAssetAllowances(bobAcc, alice, assetAllowances);
    vm.stopPrank();

    // alice trade USDC in echange of Bob's coolToken
    vm.startPrank(alice);
    tradeTokens(aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), tradeAmount, tradeAmount, 0, tokenSubId);
    vm.stopPrank();

    // test end state
    uint256 usdcAllowanceLeft = account.positiveAssetAllowance(bobAcc, bob, usdcAsset, alice);
    uint256 tokenAllowanceLeft = account.negativeAssetAllowance(bobAcc, bob, coolAsset, alice);
    assertEq(usdcAllowanceLeft, 0);
    assertEq(tokenAllowanceLeft, 0);
  }

  function testTradeWithEnoughSubIdAllowance() public {
    uint tradeAmount = 1e18;

    vm.startPrank(bob);
    // bob allow alice to move its cool token, agree to receive USDC
    AccountStructs.SubIdAllowance[] memory tokenSubIdAllowances = new AccountStructs.SubIdAllowance[](2);
    tokenSubIdAllowances[0] = AccountStructs.SubIdAllowance({
      asset: coolAsset,
      subId: tokenSubId,
      positive: 0,
      negative: tradeAmount
    });
    tokenSubIdAllowances[1] = AccountStructs.SubIdAllowance({
      asset: usdcAsset,
      subId: 0,
      positive: tradeAmount,
      negative: 0
    });
    account.setSubIdAllowances(bobAcc, alice, tokenSubIdAllowances);
    vm.stopPrank();

    // alice trade USDC in echange of Bob's coolToken
    vm.startPrank(alice);
    tradeTokens(aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), 1e18, 1e18, 0, tokenSubId);
    vm.stopPrank();

    // test end state
    uint256 usdcAllowanceLeft = account.positiveSubIdAllowance(bobAcc, bob, usdcAsset, 0, alice);
    uint256 tokenAllowanceLeft = account.negativeSubIdAllowance(bobAcc, bob, coolAsset, tokenSubId, alice);
    assertEq(usdcAllowanceLeft, 0);
    assertEq(tokenAllowanceLeft, 0);
  }

  function testTradeWithEnoughTotalAllowance() public {
    uint tradeAmount = 1e18;

    vm.startPrank(bob);
    // bob allow alice to move its cool token, agree to receive USDC
    AccountStructs.AssetAllowance[] memory assetAllowances = new AccountStructs.AssetAllowance[](2);
    assetAllowances[0] = AccountStructs.AssetAllowance({
      asset: coolAsset,
      positive: 0,
      negative: tradeAmount / 2
    });
    assetAllowances[1] = AccountStructs.AssetAllowance({
      asset: usdcAsset,
      positive: tradeAmount / 2,
      negative: 0
    });
    account.setAssetAllowances(bobAcc, alice, assetAllowances);

    AccountStructs.SubIdAllowance[] memory tokenSubIdAllowances = new AccountStructs.SubIdAllowance[](2);
    tokenSubIdAllowances[0] = AccountStructs.SubIdAllowance({
      asset: coolAsset,
      subId: tokenSubId,
      positive: 0,
      negative: tradeAmount / 2
    });
    tokenSubIdAllowances[1] = AccountStructs.SubIdAllowance({
      asset: usdcAsset,
      subId: 0,
      positive: tradeAmount / 2,
      negative: 0
    });
    account.setSubIdAllowances(bobAcc, alice, tokenSubIdAllowances);
    vm.stopPrank();

    // alice trade USDC in echange of Bob's coolToken
    vm.startPrank(alice);
    tradeTokens(aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), tradeAmount, tradeAmount, 0, tokenSubId);
    vm.stopPrank();

    // all allowance are spent now
    assertEq(account.positiveSubIdAllowance(bobAcc, bob, usdcAsset, 0, alice), 0);
    assertEq(account.negativeSubIdAllowance(bobAcc, bob, coolAsset, tokenSubId, alice), 0);
    assertEq(account.positiveAssetAllowance(bobAcc, bob, usdcAsset, alice), 0);
    assertEq(account.negativeAssetAllowance(bobAcc, bob, coolAsset, alice), 0);
  }

  function testCannotTradeWithPartialNegativeAllowance() public {    

    vm.startPrank(bob);
    // bob allow alice to move its cool token, agree to receive USDC
    AccountStructs.AssetAllowance[] memory assetAllowances = new AccountStructs.AssetAllowance[](2);
    assetAllowances[0] = AccountStructs.AssetAllowance({
      asset: coolAsset,
      positive: 0,
      negative: 5e17
    });
    assetAllowances[1] = AccountStructs.AssetAllowance({
      asset: usdcAsset,
      positive: 1e18,
      negative: 0
    });
    account.setAssetAllowances(bobAcc, alice, assetAllowances);

    AccountStructs.SubIdAllowance[] memory tokenSubIdAllowances = new AccountStructs.SubIdAllowance[](2);
    tokenSubIdAllowances[0] = AccountStructs.SubIdAllowance({
      asset: coolAsset,
      subId: tokenSubId,
      positive: 0,
      negative: 4e17
    });
    tokenSubIdAllowances[1] = AccountStructs.SubIdAllowance({
      asset: usdcAsset,
      subId: 0,
      positive: 1e18,
      negative: 0
    });
    account.setSubIdAllowances(bobAcc, alice, tokenSubIdAllowances);
    vm.stopPrank();

    // expect revert
    vm.startPrank(alice);
    vm.expectRevert(
      abi.encodeWithSelector(IAllowances.NotEnoughSubIdOrAssetAllowances.selector, 
        address(account), 
        alice,
        bobAcc,
        -1e18,
        4e17, // tokenSubId allowance
        5e17  // asset allowance
      )
    );

    // alice trade USDC in echange of Bob's coolToken
    tradeTokens(aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), 1e18, 1e18, 0, tokenSubId);
    vm.stopPrank();
  }

  function testCannotTradeWithInsufficientPositiveAllowance() public {    
    // trade will revert if receiver doesn't specify allowance to increase its position
    uint tradeAmount = 1e18;

    vm.startPrank(bob);
    // bob allow alice to move its cool token
    AccountStructs.AssetAllowance[] memory assetAllowances = new AccountStructs.AssetAllowance[](1);
    assetAllowances[0] = AccountStructs.AssetAllowance({
      asset: coolAsset,
      positive: 0,
      negative: tradeAmount
    });
    account.setAssetAllowances(bobAcc, alice, assetAllowances);
    vm.stopPrank();

    // expect revert
    vm.startPrank(alice);
    vm.expectRevert(
      abi.encodeWithSelector(IAllowances.NotEnoughSubIdOrAssetAllowances.selector, 
        address(account), 
        alice,
        bobAcc,
        tradeAmount, // cannot increase amount!
        0, // tokenSubId allowance
        0  // asset allowance
      )
    );

    // alice trade USDC in echange of Bob's coolToken
    tradeTokens(aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), tradeAmount, tradeAmount, 0, tokenSubId);
    vm.stopPrank();
  }

  function test3rdPartyAllowance() public {    
    address orderbook = address(0xb00c);

    // give orderbook allowance over both
    AccountStructs.AssetAllowance[] memory assetAllowances = new AccountStructs.AssetAllowance[](2);
    assetAllowances[0] = AccountStructs.AssetAllowance({
      asset: coolAsset,
      positive: type(uint).max,
      negative: type(uint).max
    });
    assetAllowances[1] = AccountStructs.AssetAllowance({
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
    tradeTokens(aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), 1e18, 1e18, 0, tokenSubId);
    vm.stopPrank();
  }

  function testCannotTradeBy3rdPartyWithoutAllowance() public {    
    address orderbook = address(0xb00c);

    // bob give orderbook allowance over both
    AccountStructs.AssetAllowance[] memory assetAllowances = new AccountStructs.AssetAllowance[](2);
    assetAllowances[0] = AccountStructs.AssetAllowance({
      asset: coolAsset,
      positive: type(uint).max,
      negative: type(uint).max
    });
    assetAllowances[1] = AccountStructs.AssetAllowance({
      asset: usdcAsset,
      positive: type(uint).max,
      negative: type(uint).max
    });

    vm.startPrank(bob);
    account.setAssetAllowances(bobAcc, orderbook, assetAllowances);
    vm.stopPrank();

    // alice gives wrong tokenSubId allowance for tokenAsset asset
    vm.startPrank(alice);
    AccountStructs.SubIdAllowance[] memory tokenSubIdAllowances = new AccountStructs.SubIdAllowance[](2);
    tokenSubIdAllowances[0] = AccountStructs.SubIdAllowance({
      asset: coolAsset,
      subId: tokenSubId + 1, // wrong tokenSubId 
      positive: type(uint).max,
      negative: type(uint).max
    });
    tokenSubIdAllowances[1] = AccountStructs.SubIdAllowance({
      asset: usdcAsset,
      subId: 0,
      positive: type(uint).max,
      negative: type(uint).max
    });
    account.setSubIdAllowances(aliceAcc, orderbook, tokenSubIdAllowances);
    vm.stopPrank();

    // expect revert
    vm.startPrank(orderbook);
    vm.expectRevert(
      abi.encodeWithSelector(IAllowances.NotEnoughSubIdOrAssetAllowances.selector, 
        address(account), 
        orderbook,
        aliceAcc,
        5e17,
        0,
        0
      )
    );
    tradeTokens(aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), 1e18, 5e17, 0, tokenSubId);
    vm.stopPrank();
  }

  function testERC721Approval() public {    
    uint tradeAmount = 1e18;
    
    vm.startPrank(bob);
    account.approve(alice, bobAcc);
    vm.stopPrank();

    // successful trade
    vm.startPrank(alice);
    tradeTokens(aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), tradeAmount, tradeAmount, 0, tokenSubId);
    vm.stopPrank();
  }

  function testERC721ApprovalForAll() public {    
    uint tradeAmount = 1e18;

    vm.startPrank(bob);
    account.setApprovalForAll(alice, true);
    vm.stopPrank();

    // successful trade
    vm.startPrank(alice);
    tradeTokens(aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), tradeAmount, tradeAmount, 0, tokenSubId);
    vm.stopPrank();

    // successful trade even with new account from same user
    uint bobNewAcc = account.createAccount(bob, dumbManager);
    mintAndDeposit(
      bob,
      bobNewAcc,
      coolToken,
      coolAsset,
      tokenSubId,
      tradeAmount
    );    

    vm.startPrank(alice);
    tradeTokens(aliceAcc, bobNewAcc, address(usdcAsset), address(coolAsset), tradeAmount, tradeAmount, 0, tokenSubId);
    vm.stopPrank();
  }

  function testManagerInitiatedTransfer() public {    
    // successful trade without allowances
    vm.startPrank(address(dumbManager));
    tradeTokens(aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), 1e18, 1e18, 0, tokenSubId);
    vm.stopPrank();
  }

  function testAutoAllowanceWithNewAccount() public {    
    // new user account with spender allowance
    vm.startPrank(alice);
    address user = vm.addr(100);
    uint userAcc = account.createAccountWithApproval(user, bob, dumbManager);
    vm.stopPrank();
    mintAndDeposit(
        user,
        userAcc,
        usdc,
        usdcAsset,
        0,
        1e18
    );

    // successful trade without allowances
    vm.startPrank(bob);
    tradeTokens(userAcc, bobAcc, address(usdcAsset), address(coolAsset), 1e18, 1e18, 0, tokenSubId);
    vm.stopPrank();
  }  
}