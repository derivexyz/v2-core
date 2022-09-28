// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../../../src/interfaces/IAccount.sol";

import {DumbManager} from "../../mocks/managers/DumbManager.sol";
import {DumbAsset} from "../../mocks/assets/DumbAsset.sol";

import {AccountTestBase} from "./AccountTestBase.sol";

contract UNIT_AccountBasic is Test, AccountTestBase {

  function setUp() public {
    setUpAccounts();
  } 

  function testCannotTransferToSelf() public {
    vm.expectRevert(
      abi.encodeWithSelector(IAccount.CannotTransferAssetToOneself.selector, 
        address(account), 
        alice,
        aliceAcc
      )
    );
    vm.prank(alice);
    transferToken(aliceAcc, aliceAcc, usdcAsset, 0, 1e18);
  }

  // @note: do we want to allow this
  function testCanTransferToAnyoneWith0Amount() public {
    vm.prank(alice);
    transferToken(aliceAcc, bobAcc, usdcAsset, 0, 0);
  }

  function testTransfersUpdateBalances() public {
    // set allowance from bob and alice to allow trades
    vm.prank(bob);
    account.approve(address(this), bobAcc);
    vm.prank(alice);
    account.approve(address(this), aliceAcc);

    int usdcAmount = 1e18;
    int coolAmount = 2e18;

    int aliceUsdcBefore = account.getBalance(aliceAcc, usdcAsset, 0);
    int bobUsdcBefore = account.getBalance(bobAcc, usdcAsset, 0);

    int aliceCoolBefore = account.getBalance(aliceAcc, coolAsset, tokenSubId);
    int bobCoolBefore = account.getBalance(bobAcc, coolAsset, tokenSubId);

    IAccount.AssetBalance[] memory aliceBalances = account.getAccountBalances(aliceAcc);
    IAccount.AssetBalance[] memory bobBalances = account.getAccountBalances(bobAcc);
    assertEq(aliceBalances.length, 1);
    assertEq(bobBalances.length, 1);

    tradeTokens(aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), uint(usdcAmount), uint(coolAmount), 0, tokenSubId);

    int aliceUsdcAfter = account.getBalance(aliceAcc, usdcAsset, 0);
    int bobUsdcAfter = account.getBalance(bobAcc, usdcAsset, 0);

    int aliceCoolAfter = account.getBalance(aliceAcc, coolAsset, tokenSubId);
    int bobCoolAfter = account.getBalance(bobAcc, coolAsset, tokenSubId);

    assertEq((aliceUsdcBefore - aliceUsdcAfter), usdcAmount);
    assertEq((bobUsdcAfter - bobUsdcBefore), usdcAmount);
    assertEq((aliceCoolAfter - aliceCoolBefore), coolAmount);
    assertEq((bobCoolBefore - bobCoolAfter), coolAmount);

    // requesting AssetBalance should also return new data
    aliceBalances = account.getAccountBalances(aliceAcc);
    bobBalances = account.getAccountBalances(bobAcc);
    assertEq(aliceBalances.length, 2);
    assertEq(bobBalances.length, 2);

    assertEq(address(aliceBalances[1].asset), address(coolAsset));
    assertEq(aliceBalances[1].subId, tokenSubId);
    assertEq(aliceBalances[1].balance, coolAmount);

    assertEq(address(bobBalances[1].asset), address(usdcAsset));
    assertEq(bobBalances[1].subId, 0);
    assertEq(bobBalances[1].balance, usdcAmount);
  }

  function testCannotBurnNonEmptyAccount() public {
    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(
      IAccount.CannotBurnAccountWithHeldAssets.selector,
      address(account),
      alice,
      aliceAcc,
      1
    ));
    account.burnAccount(aliceAcc);
  }

  function testBurnEmptyAccount() public {
    vm.startPrank(alice);
    uint emptyAcc = account.createAccount(alice, dumbManager);
    account.burnAccount(emptyAcc);
    vm.stopPrank();

    // can no longer access this NFT
    vm.expectRevert(bytes("ERC721: invalid token ID"));
    account.ownerOf(emptyAcc);
  }

  // @note: will this cause some trouble or open up concerns?
  function testCanBurnFromApprovedParties() public {
    vm.startPrank(alice);
    uint emptyAcc = account.createAccount(alice, dumbManager);
    account.approve(address(this), emptyAcc);
    vm.stopPrank();

    // can be burn from this address
    account.burnAccount(emptyAcc);
  }

  function testCanAdjustBalanceFromManager() public {
    uint newAccount = account.createAccount(address(this), dumbManager);
    int amount = 1000e18;

    vm.prank(address(dumbManager));
    account.adjustBalance(IAccount.AssetAdjustment({
        acc: newAccount, 
        asset: usdcAsset, 
        subId: 0,
        amount: amount,
        assetData: bytes32(0)
    }));

    assertEq(account.getBalance(newAccount, usdcAsset, 0), amount);
  }

  function testAssetCanRevertAdjustmentByBadManager() public {
    uint newAccount = account.createAccount(address(this), dumbManager);
    int amount = 1000e18;

    // assume usdc now block adjustment from dumbManager
    usdcAsset.setRevertAdjustmentFromManager(address(dumbManager), true);

    vm.prank(address(dumbManager));
    vm.expectRevert();
    account.adjustBalance(IAccount.AssetAdjustment({
        acc: newAccount, 
        asset: usdcAsset, 
        subId: 0,
        amount: amount,
        assetData: bytes32(0)
    }));
  }

}