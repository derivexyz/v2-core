// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../../../src/interfaces/IAccount.sol";
import "../../../src/interfaces/AccountStructs.sol";
import "../../../src/Allowances.sol";
import {AccountTestBase} from "./AccountTestBase.sol";

contract UNIT_Allowances is Test, AccountTestBase {
  
  function setUp() public {
    setUpAccounts();
  }

  function testCanTransferWithoutPositiveAllowance() public {
    int256 amount = 1e18;
    vm.startPrank(alice);
    transferToken(aliceAcc, bobAcc, usdcAsset, 0, amount);
    vm.stopPrank();
  }

  function testCannotTradeWithoutAllowance() public {    
    // expect revert
    vm.startPrank(alice);
    vm.expectRevert(
      abi.encodeWithSelector(Allowances.NotEnoughSubIdOrAssetAllowances.selector, 
        address(account), 
        alice,
        bobAcc,
        -1e18,
        0,
        0
      )
    );
    tradeTokens(aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), 1e18, 1e18, 0, tokenSubId);
    vm.stopPrank();
  }

  function testTradeWithEnoughAssetAllowance() public {
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

    // alice trade USDC in echange of Bob's coolToken
    vm.startPrank(alice);
    tradeTokens(aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), tradeAmount, tradeAmount, 0, tokenSubId);
    vm.stopPrank();

    // test end state
    uint256 usdcAllowanceLeft = account.positiveAssetAllowance(bobAcc, bob, usdcAsset, alice);
    assertEq(usdcAllowanceLeft, 0);
  }

  function testTradeWithEnoughSubIdAllowance() public {
    uint tradeAmount = 1e18;

    vm.startPrank(bob);
    // bob allow alice to move its cool token
    AccountStructs.SubIdAllowance[] memory tokenSubIdAllowances = new AccountStructs.SubIdAllowance[](1);
    tokenSubIdAllowances[0] = AccountStructs.SubIdAllowance({
      asset: coolAsset,
      subId: tokenSubId,
      positive: 0,
      negative: tradeAmount
    });
    account.setSubIdAllowances(bobAcc, alice, tokenSubIdAllowances);
    vm.stopPrank();

    // alice trade USDC in echange of Bob's coolToken
    vm.startPrank(alice);
    tradeTokens(aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), 1e18, 1e18, 0, tokenSubId);
    vm.stopPrank();

    // test end state
    uint256 tokenAllowanceLeft = account.negativeSubIdAllowance(bobAcc, bob, coolAsset, tokenSubId, alice);
    assertEq(tokenAllowanceLeft, 0);
  }

  function testTradeWithEnoughTotalAllowance() public {
    uint tradeAmount = 1e18;

    vm.startPrank(bob);
    // bob allow alice to move its cool token both on "asset" and "subIdAllowance"
    AccountStructs.AssetAllowance[] memory assetAllowances = new AccountStructs.AssetAllowance[](1);
    assetAllowances[0] = AccountStructs.AssetAllowance({
      asset: coolAsset,
      positive: 0,
      negative: tradeAmount / 2
    });
    account.setAssetAllowances(bobAcc, alice, assetAllowances);

    AccountStructs.SubIdAllowance[] memory tokenSubIdAllowances = new AccountStructs.SubIdAllowance[](1);
    tokenSubIdAllowances[0] = AccountStructs.SubIdAllowance({
      asset: coolAsset,
      subId: tokenSubId,
      positive: 0,
      negative: tradeAmount / 2
    });
    account.setSubIdAllowances(bobAcc, alice, tokenSubIdAllowances);
    vm.stopPrank();

    // alice trade USDC in echange of Bob's coolToken
    vm.startPrank(alice);
    tradeTokens(aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), tradeAmount, tradeAmount, 0, tokenSubId);
    vm.stopPrank();

    // all allowance are spent now
    assertEq(account.negativeSubIdAllowance(bobAcc, bob, coolAsset, tokenSubId, alice), 0);
    assertEq(account.negativeAssetAllowance(bobAcc, bob, coolAsset, alice), 0);
  }

  function testCannotTradeWithInsufficientTotalAllowance() public {    

    vm.startPrank(bob);
    // bob allow alice to move its cool token
    AccountStructs.AssetAllowance[] memory assetAllowances = new AccountStructs.AssetAllowance[](1);
    assetAllowances[0] = AccountStructs.AssetAllowance({
      asset: coolAsset,
      positive: 0,
      negative: 5e17
    });
    account.setAssetAllowances(bobAcc, alice, assetAllowances);

    AccountStructs.SubIdAllowance[] memory tokenSubIdAllowances = new AccountStructs.SubIdAllowance[](1);
    tokenSubIdAllowances[0] = AccountStructs.SubIdAllowance({
      asset: coolAsset,
      subId: tokenSubId,
      positive: 0,
      negative: 4e17
    });
    account.setSubIdAllowances(bobAcc, alice, tokenSubIdAllowances);
    vm.stopPrank();

    // expect revert
    vm.startPrank(alice);
    vm.expectRevert(
      abi.encodeWithSelector(Allowances.NotEnoughSubIdOrAssetAllowances.selector, 
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
    uint tradeAmount = 1e18;

    // set that we need positive allowance to receive USDC
    usdcAsset.setNeedPositiveAllowance(true);

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
      abi.encodeWithSelector(Allowances.NotEnoughSubIdOrAssetAllowances.selector, 
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

  function testERC721TranserShouldNotTransferAllowance() public {
    address charlie = address(0xcc);
    uint tradeAmount = 1e18;

    vm.startPrank(bob);
    AccountStructs.AssetAllowance[] memory assetAllowances = new AccountStructs.AssetAllowance[](1);
    assetAllowances[0] = AccountStructs.AssetAllowance({
      asset: coolAsset,
      positive: 0,
      negative: tradeAmount
    });
    account.setAssetAllowances(bobAcc, alice, assetAllowances);
    account.transferFrom(bob, charlie, bobAcc);  // transfer account to charlie
    vm.stopPrank();

    uint charlieAcc = bobAcc;

    // should revert because allowance is not transferred 
    vm.startPrank(alice);
    vm.expectRevert(
      abi.encodeWithSelector(Allowances.NotEnoughSubIdOrAssetAllowances.selector, 
        address(account), 
        alice,
        charlieAcc,
        -1e18,
        0,
        0
      )
    );
    tradeTokens(aliceAcc, charlieAcc, address(usdcAsset), address(coolAsset), tradeAmount, tradeAmount, 0, tokenSubId);
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