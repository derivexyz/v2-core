// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../../../src/Account.sol";

import {MockManager} from "../../shared/mocks/MockManager.sol";
import {MockAsset} from "../../shared/mocks/MockAsset.sol";

import {AccountTestBase} from "./AccountTestBase.sol";

contract UNIT_AccountBasic is Test, AccountTestBase {
  function setUp() public {
    setUpAccounts();
  }

  function testCannotTransferToSelf() public {
    vm.expectRevert(
      abi.encodeWithSelector(Account.CannotTransferAssetToOneself.selector, address(account), alice, aliceAcc)
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

    AccountStructs.AssetBalance[] memory aliceBalances = account.getAccountBalances(aliceAcc);
    AccountStructs.AssetBalance[] memory bobBalances = account.getAccountBalances(bobAcc);
    assertEq(aliceBalances.length, 1);
    assertEq(bobBalances.length, 1);

    tradeTokens(
      aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), uint(usdcAmount), uint(coolAmount), 0, tokenSubId
    );

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

  /**
   * =================================================
   * test  hook data pass to Manager.handleAdjustment |
   * =================================================
   */

  function testAdjustmentHookTriggeredCorrectly() public {
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

    AccountStructs.AssetBalance[] memory aliceBalances = account.getAccountBalances(aliceAcc);
    AccountStructs.AssetBalance[] memory bobBalances = account.getAccountBalances(bobAcc);
    assertEq(aliceBalances.length, 1);
    assertEq(bobBalances.length, 1);

    tradeTokens(
      aliceAcc, bobAcc, address(usdcAsset), address(coolAsset), uint(usdcAmount), uint(coolAmount), 0, tokenSubId
    );

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

  /**
   * ==========================================================
   * tests for call flow rom Manager => Account.adjustBalance() |
   * ========================================================== *
   */

  function testCanAdjustBalanceFromManager() public {
    uint newAccount = account.createAccount(address(this), dumbManager);
    int amount = 1000e18;

    vm.prank(address(dumbManager));
    account.managerAdjustment(
      AccountStructs.AssetAdjustment({
        acc: newAccount,
        asset: usdcAsset,
        subId: 0,
        amount: amount,
        assetData: bytes32(0)
      })
    );

    assertEq(account.getBalance(newAccount, usdcAsset, 0), amount);
  }

  function testAssetCanRevertAdjustmentByBadManager() public {
    uint newAccount = account.createAccount(address(this), dumbManager);
    int amount = 1000e18;

    // assume usdc now block adjustment from dumbManager
    usdcAsset.setRevertAdjustmentFromManager(address(dumbManager), true);

    vm.prank(address(dumbManager));
    vm.expectRevert();
    account.managerAdjustment(
      AccountStructs.AssetAdjustment({
        acc: newAccount,
        asset: usdcAsset,
        subId: 0,
        amount: amount,
        assetData: bytes32(0)
      })
    );
  }

  /**
   * =========================================================
   * tests for call flow rom Asset => Account.adjustBalance()  |
   * ========================================================= *
   */

  function testCanAdjustBalanceFromAsset() public {
    uint newAccount = account.createAccount(address(this), dumbManager);
    int amount = 1000e18;

    // assume calls from usdc
    vm.prank(address(usdcAsset));
    account.assetAdjustment(
      AccountStructs.AssetAdjustment({
        acc: newAccount,
        asset: usdcAsset,
        subId: 0,
        amount: amount,
        assetData: bytes32(0)
      }),
      false,
      ""
    );

    assertEq(account.getBalance(newAccount, usdcAsset, 0), amount);
  }

  function testCannotAdjustBalanceForAnotherAsset() public {
    uint newAccount = account.createAccount(address(this), dumbManager);
    int amount = 1000e18;

    // assume calls from coolAsset
    vm.prank(address(coolAsset));

    vm.expectRevert(
      abi.encodeWithSelector(Account.OnlyAsset.selector, address(account), address(coolAsset), address(usdcAsset))
    );
    account.assetAdjustment(
      AccountStructs.AssetAdjustment({
        acc: newAccount,
        asset: usdcAsset,
        subId: 0,
        amount: amount,
        assetData: bytes32(0)
      }),
      true,
      ""
    );
  }

  /**
   * ============================== *
   * tests for updating heldAssets   |
   * =============================== *
   *
   */

  function testAssetHeldArrayUpdateCorrectly() public {
    vm.prank(bob);
    account.approve(address(this), bobAcc);
    vm.prank(alice);
    account.approve(address(this), aliceAcc);

    int aliceUsdcBefore = account.getBalance(aliceAcc, usdcAsset, 0);
    int bobCoolBefore = account.getBalance(bobAcc, coolAsset, tokenSubId);

    (IAsset aliceAsset0Befire,) = account.heldAssets(aliceAcc, 0);
    (IAsset bobAsset0Before,) = account.heldAssets(bobAcc, 0);
    assertEq(address(aliceAsset0Befire), address(usdcAsset));
    assertEq(address(bobAsset0Before), address(coolAsset));

    tradeTokens(
      aliceAcc,
      bobAcc,
      address(usdcAsset),
      address(coolAsset),
      uint(aliceUsdcBefore),
      uint(bobCoolBefore),
      0,
      tokenSubId
    );

    // held asset now updated
    (IAsset aliceAsset0After,) = account.heldAssets(aliceAcc, 0);
    (IAsset bobAsset0After,) = account.heldAssets(bobAcc, 0);
    assertEq(address(aliceAsset0After), address(coolAsset));
    assertEq(address(bobAsset0After), address(usdcAsset));
  }
}
