// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../../shared/mocks/MockERC20.sol";
import "../../shared/mocks/MockAsset.sol";
import {ISubAccounts} from "../../../src/interfaces/ISubAccounts.sol";
import "../../../src/Allowances.sol";
import "../../../src/SubAccounts.sol";
import {AccountTestBase} from "./AccountTestBase.sol";

contract UNIT_Allowances is Test, AccountTestBase {
  function setUp() public {
    setUpAccounts();
  }

  function testCanTransferWithoutPositiveAllowance() public {
    int amount = 1e18;
    vm.startPrank(alice);
    transferToken(aliceAcc, bobAcc, usdcAsset, 0, amount);
    vm.stopPrank();
  }

  function testCannotSetAllowanceFromNonOwner() public {
    IAllowances.AssetAllowance[] memory assetAllowances = new IAllowances.AssetAllowance[](0);
    vm.expectRevert(
      abi.encodeWithSelector(
        ISubAccounts.AC_NotOwnerOrERC721Approved.selector, alice, bobAcc, bob, address(dumbManager), address(0)
      )
    );
    vm.prank(alice);
    subAccounts.setAssetAllowances(bobAcc, alice, assetAllowances);
  }

  function testCannotTransferNegativeAllowanceWithoutAllowance() public {
    int amount = 1e18;
    vm.expectRevert(
      abi.encodeWithSelector(IAllowances.NotEnoughSubIdOrAssetAllowances.selector, alice, bobAcc, -1e18, 0, 0)
    );
    vm.startPrank(alice);
    transferToken(aliceAcc, bobAcc, coolAsset, tokenSubId, -amount);
    vm.stopPrank();
  }

  function testCannotTradeWithoutAllowance() public {
    // expect revert
    vm.startPrank(alice);
    vm.expectRevert(
      abi.encodeWithSelector(IAllowances.NotEnoughSubIdOrAssetAllowances.selector, alice, bobAcc, -1e18, 0, 0)
    );
    tradeTokens(aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), 1e18, 1e18, 0, tokenSubId);
    vm.stopPrank();
  }

  function testTradeWithEnoughAssetAllowance() public {
    uint tradeAmount = 1e18;

    vm.startPrank(bob);
    // bob allow alice to move its cool token
    IAllowances.AssetAllowance[] memory assetAllowances = new IAllowances.AssetAllowance[](1);
    assetAllowances[0] = IAllowances.AssetAllowance({asset: coolAsset, positive: 0, negative: tradeAmount});
    subAccounts.setAssetAllowances(bobAcc, alice, assetAllowances);
    vm.stopPrank();

    // alice trade USDC in echange of Bob's coolToken
    vm.startPrank(alice);
    tradeTokens(aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), tradeAmount, tradeAmount, 0, tokenSubId);
    vm.stopPrank();

    // test end state
    uint usdcAllowanceLeft = subAccounts.positiveAssetAllowance(bobAcc, bob, usdcAsset, alice);
    assertEq(usdcAllowanceLeft, 0);
  }

  function testTradeWithEnoughSubIdAllowance() public {
    uint tradeAmount = 1e18;

    vm.startPrank(bob);
    // bob allow alice to move its cool token
    IAllowances.SubIdAllowance[] memory tokenSubIdAllowances = new IAllowances.SubIdAllowance[](1);
    tokenSubIdAllowances[0] =
      IAllowances.SubIdAllowance({asset: coolAsset, subId: tokenSubId, positive: 0, negative: tradeAmount});
    subAccounts.setSubIdAllowances(bobAcc, alice, tokenSubIdAllowances);
    vm.stopPrank();

    // alice trade USDC in echange of Bob's coolToken
    vm.startPrank(alice);
    tradeTokens(aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), 1e18, 1e18, 0, tokenSubId);
    vm.stopPrank();

    // test end state
    uint tokenAllowanceLeft = subAccounts.negativeSubIdAllowance(bobAcc, bob, coolAsset, tokenSubId, alice);
    assertEq(tokenAllowanceLeft, 0);
  }

  function testTradeWithEnoughTotalAllowance() public {
    uint tradeAmount = 1e18;

    vm.startPrank(bob);
    // bob allow alice to move its cool token both on "asset" and "subIdAllowance"
    IAllowances.AssetAllowance[] memory assetAllowances = new IAllowances.AssetAllowance[](1);
    assetAllowances[0] = IAllowances.AssetAllowance({asset: coolAsset, positive: 0, negative: tradeAmount / 2});
    subAccounts.setAssetAllowances(bobAcc, alice, assetAllowances);

    IAllowances.SubIdAllowance[] memory tokenSubIdAllowances = new IAllowances.SubIdAllowance[](1);
    tokenSubIdAllowances[0] =
      IAllowances.SubIdAllowance({asset: coolAsset, subId: tokenSubId, positive: 0, negative: tradeAmount / 2});
    subAccounts.setSubIdAllowances(bobAcc, alice, tokenSubIdAllowances);
    vm.stopPrank();

    // alice trade USDC in echange of Bob's coolToken
    vm.startPrank(alice);
    tradeTokens(aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), tradeAmount, tradeAmount, 0, tokenSubId);
    vm.stopPrank();

    // all allowance are spent now
    assertEq(subAccounts.negativeSubIdAllowance(bobAcc, bob, coolAsset, tokenSubId, alice), 0);
    assertEq(subAccounts.negativeAssetAllowance(bobAcc, bob, coolAsset, alice), 0);
  }

  function testCannotTradeWithInsufficientTotalAllowance() public {
    vm.startPrank(bob);
    // bob allow alice to move its cool token
    IAllowances.AssetAllowance[] memory assetAllowances = new IAllowances.AssetAllowance[](1);
    assetAllowances[0] = IAllowances.AssetAllowance({asset: coolAsset, positive: 0, negative: 5e17});
    subAccounts.setAssetAllowances(bobAcc, alice, assetAllowances);

    IAllowances.SubIdAllowance[] memory tokenSubIdAllowances = new IAllowances.SubIdAllowance[](1);
    tokenSubIdAllowances[0] =
      IAllowances.SubIdAllowance({asset: coolAsset, subId: tokenSubId, positive: 0, negative: 4e17});
    subAccounts.setSubIdAllowances(bobAcc, alice, tokenSubIdAllowances);
    vm.stopPrank();

    // expect revert
    vm.startPrank(alice);
    vm.expectRevert(
      abi.encodeWithSelector(
        IAllowances.NotEnoughSubIdOrAssetAllowances.selector,
        alice,
        bobAcc,
        -1e18,
        4e17, // tokenSubId allowance
        5e17 // asset allowance
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
    IAllowances.AssetAllowance[] memory assetAllowances = new IAllowances.AssetAllowance[](1);
    assetAllowances[0] = IAllowances.AssetAllowance({asset: coolAsset, positive: 0, negative: tradeAmount});
    subAccounts.setAssetAllowances(bobAcc, alice, assetAllowances);
    vm.stopPrank();

    // expect revert
    vm.startPrank(alice);
    vm.expectRevert(
      abi.encodeWithSelector(
        IAllowances.NotEnoughSubIdOrAssetAllowances.selector,
        alice,
        bobAcc,
        tradeAmount, // cannot increase amount!
        0, // tokenSubId allowance
        0 // asset allowance
      )
    );

    // alice trade USDC in echange of Bob's coolToken
    tradeTokens(aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), tradeAmount, tradeAmount, 0, tokenSubId);
    vm.stopPrank();
  }

  function test3rdPartyAllowance() public {
    address orderbook = address(0xb00c);

    // give orderbook allowance over both
    IAllowances.AssetAllowance[] memory assetAllowances = new IAllowances.AssetAllowance[](2);
    assetAllowances[0] =
      IAllowances.AssetAllowance({asset: coolAsset, positive: type(uint).max, negative: type(uint).max});
    assetAllowances[1] =
      IAllowances.AssetAllowance({asset: usdcAsset, positive: type(uint).max, negative: type(uint).max});

    vm.startPrank(bob);
    subAccounts.setAssetAllowances(bobAcc, orderbook, assetAllowances);
    vm.stopPrank();

    vm.startPrank(alice);
    subAccounts.setAssetAllowances(aliceAcc, orderbook, assetAllowances);
    vm.stopPrank();

    vm.startPrank(orderbook);
    tradeTokens(aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), 1e18, 1e18, 0, tokenSubId);
    vm.stopPrank();
  }

  function testCanTransferNegativeAmountOnSpecificAsset() public {
    // Imagine an "asset" that has value when balance is negative
    MockERC20 debtToken = new MockERC20("negative USD", "nUSD");
    MockAsset debtAsset = new MockAsset(IERC20(debtToken), ISubAccounts(address(subAccounts)), true);
    debtAsset.setNeedNegativeAllowance(false); // don't need allowance to decrease balance
    debtAsset.setNeedPositiveAllowance(true); // need allowance to increase balance

    // can transfer negative amount
    int amount = 1e18;

    vm.startPrank(alice);
    transferToken(aliceAcc, bobAcc, debtAsset, 0, -amount);

    // cannot transfer positive amount
    vm.expectRevert(
      abi.encodeWithSelector(IAllowances.NotEnoughSubIdOrAssetAllowances.selector, alice, bobAcc, 1e18, 0, 0)
    );
    transferToken(aliceAcc, bobAcc, debtAsset, 0, amount);
    vm.stopPrank();

    // can transfer positive amount after setting positive allowance
    IAllowances.AssetAllowance[] memory assetAllowances = new IAllowances.AssetAllowance[](1);
    assetAllowances[0] = IAllowances.AssetAllowance({asset: debtAsset, positive: uint(amount), negative: 0});
    vm.prank(bob);
    subAccounts.setAssetAllowances(bobAcc, alice, assetAllowances);

    // transfer should pass
    vm.prank(alice);
    transferToken(aliceAcc, bobAcc, debtAsset, 0, amount);
  }

  function testERC721TranserShouldNotTransferAllowance() public {
    address charlie = address(0xcc);
    uint tradeAmount = 1e18;

    vm.startPrank(bob);
    IAllowances.AssetAllowance[] memory assetAllowances = new IAllowances.AssetAllowance[](1);
    assetAllowances[0] = IAllowances.AssetAllowance({asset: coolAsset, positive: 0, negative: tradeAmount});
    subAccounts.setAssetAllowances(bobAcc, alice, assetAllowances);
    subAccounts.transferFrom(bob, charlie, bobAcc); // transfer account to charlie
    vm.stopPrank();

    uint charlieAcc = bobAcc;

    // should revert because allowance is not transferred
    vm.startPrank(alice);
    vm.expectRevert(
      abi.encodeWithSelector(IAllowances.NotEnoughSubIdOrAssetAllowances.selector, alice, charlieAcc, -1e18, 0, 0)
    );
    tradeTokens(aliceAcc, charlieAcc, address(usdcAsset), address(coolAsset), tradeAmount, tradeAmount, 0, tokenSubId);
    vm.stopPrank();
  }

  function testERC721Approval() public {
    uint tradeAmount = 1e18;

    vm.startPrank(bob);
    subAccounts.approve(alice, bobAcc);
    vm.stopPrank();

    // successful trade
    vm.startPrank(alice);
    tradeTokens(aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), tradeAmount, tradeAmount, 0, tokenSubId);
    vm.stopPrank();

    // revert with new account
    uint bobNewAcc = subAccounts.createAccount(bob, dumbManager);
    mintAndDeposit(bob, bobNewAcc, coolToken, coolAsset, tokenSubId, tradeAmount);
    vm.startPrank(alice);
    vm.expectRevert(
      abi.encodeWithSelector(
        IAllowances.NotEnoughSubIdOrAssetAllowances.selector, address(alice), bobNewAcc, -int(tradeAmount), 0, 0
      )
    );
    tradeTokens(aliceAcc, bobNewAcc, address(usdcAsset), address(coolAsset), tradeAmount, tradeAmount, 0, tokenSubId);
    vm.stopPrank();
  }

  function testERC721ApprovalForAll() public {
    uint tradeAmount = 1e18;

    vm.startPrank(bob);
    subAccounts.setApprovalForAll(alice, true);
    vm.stopPrank();

    // successful trade
    vm.startPrank(alice);
    tradeTokens(aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), tradeAmount, tradeAmount, 0, tokenSubId);
    vm.stopPrank();

    // successful trade even with new account from same user
    uint bobNewAcc = subAccounts.createAccount(bob, dumbManager);
    mintAndDeposit(bob, bobNewAcc, coolToken, coolAsset, tokenSubId, tradeAmount);

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
    uint userAcc = subAccounts.createAccountWithApproval(user, bob, dumbManager);
    vm.stopPrank();
    mintAndDeposit(user, userAcc, usdc, usdcAsset, 0, 1e18);

    // successful trade without allowances
    vm.startPrank(bob);
    tradeTokens(userAcc, bobAcc, address(usdcAsset), address(coolAsset), 1e18, 1e18, 0, tokenSubId);
    vm.stopPrank();
  }
}
