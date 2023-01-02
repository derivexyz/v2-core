// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../../../src/Accounts.sol";
import "../../../src/libraries/AssetDeltaLib.sol";

import {MockManager} from "../../shared/mocks/MockManager.sol";
import {MockAsset} from "../../shared/mocks/MockAsset.sol";

import {AccountTestBase} from "./AccountTestBase.sol";

contract UNIT_AccountBasic is Test, AccountTestBase {
  function setUp() public {
    setUpAccounts();
  }

  function testCannotTransferToSelf() public {
    vm.expectRevert(abi.encodeWithSelector(IAccounts.AC_CannotTransferAssetToOneself.selector, alice, aliceAcc));
    vm.prank(alice);
    transferToken(aliceAcc, aliceAcc, usdcAsset, 0, 1e18);
  }

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

  function testCannotSubmitTradesWithMoreThan100Deltas() public {
    vm.prank(alice);
    account.approve(address(this), aliceAcc);

    AccountStructs.AssetTransfer[] memory transferBatch = new AccountStructs.AssetTransfer[](101);
    int amount = 1e18;
    for (uint i; i < 101; i++) {
      mintAndDeposit(alice, aliceAcc, usdc, usdcAsset, i, uint(amount));

      transferBatch[i] = AccountStructs.AssetTransfer({
        fromAcc: aliceAcc,
        toAcc: bobAcc,
        asset: IAsset(usdcAsset),
        subId: i, // make 101 unique deltas
        amount: amount,
        assetData: bytes32(0)
      });
    }

    vm.expectRevert(AssetDeltaLib.DL_DeltasTooLong.selector);
    account.submitTransfers(transferBatch, "");
  }

  /**
   * =================================================
   * test  hook data pass to Manager.handleAdjustment |
   * =================================================
   */

  function testAdjustmentHookTriggeredCorrectly() public {
    uint thisAcc = account.createAccount(address(this), dumbManager);
    mintAndDeposit(address(this), thisAcc, usdc, usdcAsset, 0, 10000000e18);
    mintAndDeposit(address(this), thisAcc, coolToken, coolAsset, tokenSubId, 10000000e18);

    // set allowance from bob and alice to allow trades
    vm.prank(bob);
    account.approve(address(this), bobAcc);
    vm.prank(alice);
    account.approve(address(this), aliceAcc);

    // start recording triggers
    dumbManager.setLogAdjustmentTriggers(true);

    int amount = 1e18;

    // trades:
    // USDC alice => bob
    // USDC this => bob
    // COOL bob => this
    // COOL this => alice
    // COOL aclie => bob

    AccountStructs.AssetTransfer[] memory transferBatch = new AccountStructs.AssetTransfer[](5);

    transferBatch[0] = AccountStructs.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: IAsset(usdcAsset),
      subId: 0,
      amount: amount,
      assetData: bytes32(0)
    });

    transferBatch[1] = AccountStructs.AssetTransfer({
      fromAcc: thisAcc,
      toAcc: bobAcc,
      asset: IAsset(usdcAsset),
      subId: 0,
      amount: amount,
      assetData: bytes32(0)
    });

    transferBatch[2] = AccountStructs.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: thisAcc,
      asset: IAsset(coolAsset),
      subId: tokenSubId,
      amount: amount,
      assetData: bytes32(0)
    });

    transferBatch[3] = AccountStructs.AssetTransfer({
      fromAcc: thisAcc,
      toAcc: aliceAcc,
      asset: IAsset(coolAsset),
      subId: tokenSubId,
      amount: amount,
      assetData: bytes32(0)
    });

    transferBatch[4] = AccountStructs.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: IAsset(coolAsset),
      subId: tokenSubId,
      amount: amount,
      assetData: bytes32(0)
    });

    account.submitTransfers(transferBatch, "");

    assertEq(dumbManager.accTriggeredDeltaLength(aliceAcc), 2);
    assertEq(dumbManager.accTriggeredDeltaLength(bobAcc), 2);
    assertEq(dumbManager.accTriggeredDeltaLength(thisAcc), 2);

    // each account-asset only got triggered once
    assertEq(dumbManager.accAssetTriggered(aliceAcc, address(usdcAsset), 0), 1);
    assertEq(dumbManager.accAssetTriggered(aliceAcc, address(coolAsset), uint96(tokenSubId)), 1);
    assertEq(dumbManager.accAssetTriggered(bobAcc, address(usdcAsset), 0), 1);
    assertEq(dumbManager.accAssetTriggered(bobAcc, address(coolAsset), uint96(tokenSubId)), 1);
    assertEq(dumbManager.accAssetTriggered(thisAcc, address(usdcAsset), 0), 1);
    assertEq(dumbManager.accAssetTriggered(thisAcc, address(coolAsset), uint96(tokenSubId)), 1);

    // USDC delta passed into manager were corret
    assertEq(dumbManager.accAssetAdjustmentDelta(aliceAcc, address(usdcAsset), 0), -amount);
    assertEq(dumbManager.accAssetAdjustmentDelta(thisAcc, address(usdcAsset), 0), -amount);
    assertEq(dumbManager.accAssetAdjustmentDelta(bobAcc, address(usdcAsset), 0), 2 * amount);

    // COOL delta passed into manager were corret
    assertEq(dumbManager.accAssetAdjustmentDelta(aliceAcc, address(coolAsset), uint96(tokenSubId)), 0);
    assertEq(dumbManager.accAssetAdjustmentDelta(thisAcc, address(coolAsset), uint96(tokenSubId)), 0);
    assertEq(dumbManager.accAssetAdjustmentDelta(bobAcc, address(coolAsset), uint96(tokenSubId)), 0);
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

    vm.expectRevert(IAccounts.AC_OnlyAsset.selector);
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
