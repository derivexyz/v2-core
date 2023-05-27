// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "../../../shared/mocks/MockERC20.sol";
import "../../../shared/mocks/MockManager.sol";
import "../../../../src/assets/Option.sol";
import "../../../../src/SubAccounts.sol";

import {IOITracking} from "src/interfaces/IOITracking.sol";

/**
 * @dev testing open interest before and after
 * asset transfers
 * single side adjustments
 */
contract UNIT_OptionAssetOITest is Test {
  Option option;
  MockManager manager;
  MockManager manager2;
  SubAccounts subAccounts;

  int tradeAmount = 100e18;
  uint accountPos; // balance: 100
  uint accountNeg; // balance: -100
  uint accountEmpty; // balance: 0

  uint subId = 99999;

  function setUp() public {
    subAccounts = new SubAccounts("Lyra Margin Accounts", "LyraMarginNFTs");

    manager = new MockManager(address(subAccounts));

    manager2 = new MockManager(address(subAccounts));

    option = new Option(subAccounts, address(0));
    option.setWhitelistManager(address(manager), true);
    option.setWhitelistManager(address(manager2), true);

    accountPos = subAccounts.createAccount(address(this), manager);
    accountNeg = subAccounts.createAccount(address(this), manager);
    // init these 2 accounts with positive and negative balance
    _transfer(accountNeg, accountPos, tradeAmount);

    accountEmpty = subAccounts.createAccount(address(this), manager);

    option.setTotalPositionCap(manager, uint(10 * tradeAmount));
    option.setTotalPositionCap(manager2, uint(10 * tradeAmount));
  }

  /* --------------------- *
   |      Transfers        *
   * --------------------- */

  function testFirstTransferIncreaseOI() public {
    assertEq(option.openInterest(subId), uint(tradeAmount));
  }

  function testCloseAllPositionsMakeOIZero() public {
    _transfer(accountPos, accountNeg, tradeAmount);
    assertEq(option.openInterest(subId), 0);
  }

  function testOIPositiveToPositive() public {
    // transfer some positive amount to an empty account
    uint oiBefore = option.openInterest(subId);

    int transferAmount = 50e18;
    _transfer(accountPos, accountEmpty, transferAmount);

    assertEq(oiBefore, option.openInterest(subId));

    // transfer some more
    oiBefore = option.openInterest(subId);
    transferAmount = 10e18;
    _transfer(accountPos, accountEmpty, transferAmount);
    assertEq(oiBefore, option.openInterest(subId));
  }

  function testOIIncreaseIfIncreasePosition() public {
    uint oiBefore = option.openInterest(subId);

    // the position betweens accountPos and accountNeg increases:
    int transferAmount = 50e18;
    _transfer(accountNeg, accountPos, transferAmount);

    assertEq(oiBefore + uint(transferAmount), option.openInterest(subId));
  }

  function testOIIncreaseIfNetOpenIsBigger() public {
    // AccountPos => +100 -> -50
    // AccountNeg => -100
    // AccountEmpty => 0 -> +150
    int transferAmount = 150e18;
    _transfer(accountPos, accountEmpty, transferAmount);

    assertEq(option.openInterest(subId), 150e18);
  }

  function testOIDecreaseIfNetCloseIsBigger() public {
    // AccountPos => +100 -> +30
    // AccountNeg => -100 -> -30
    int transferAmount = 70e18;
    _transfer(accountPos, accountNeg, transferAmount);

    assertEq(option.openInterest(subId), 30e18);
  }

  function testOIUnchangedIfNegativeBalanceChangeHands() public {
    uint oiBefore = option.openInterest(subId);
    // AccountNeg => -100 -> 0
    // AccountEmpty => 0 -> -100
    _transfer(accountNeg, accountEmpty, -tradeAmount);

    assertEq(option.openInterest(subId), oiBefore);
  }

  function testOIUnchangedCase2() public {
    uint oiBefore = option.openInterest(subId);
    // AccountNeg => -100 -> +100
    // AccountPos => 100 -> -100
    _transfer(accountPos, accountNeg, tradeAmount * 2);

    assertEq(option.openInterest(subId), oiBefore);
  }

  /* ---------------------------
   *    Total position calcs
   * --------------------------*/
  function setTotalPositionCap() public {
    option.setTotalPositionCap(manager, 100);
    assertEq(option.totalPositionCap(manager), 100);
  }

  function testTotalPositionInit() public {
    // the initial state is with 1 positive account and 1 negative account
    assertEq(option.totalPosition(manager), uint(tradeAmount * 2));
  }

  function testTotalPositionUnchangedIfNoNetOpen() public {
    uint totalPosBefore = option.totalPosition(manager);

    // AccountNeg => -100 -> 0
    // AccountEmpty => 0 -> -100
    _transfer(accountEmpty, accountNeg, tradeAmount);

    uint totalPosAfter = option.totalPosition(manager);

    assertEq(totalPosBefore, totalPosAfter);
  }

  function testTotalPositionIncreaseIfBothIncrease() public {
    uint totalPosBefore = option.totalPosition(manager);

    // AccountNeg => -100 -> -200
    // AccountPos => +100 -> +200
    _transfer(accountNeg, accountPos, tradeAmount);

    uint totalPosAfter = option.totalPosition(manager);

    assertEq(totalPosBefore + uint(tradeAmount * 2), totalPosAfter);
  }

  function testTotalPositionCanDecreaseIfSomeoneClose() public {
    uint totalPosBefore = option.totalPosition(manager);

    // AccountNeg => -100 -> 0
    // AccountPos => +100 -> 0
    _transfer(accountPos, accountNeg, tradeAmount);

    uint totalPosAfter = option.totalPosition(manager);

    assertEq(totalPosBefore - uint(tradeAmount * 2), totalPosAfter);
  }

  function testCanTradeCrossManager() public {
    uint totalPos1Before = option.totalPosition(manager);

    // new account under manager 2
    uint newAcc = subAccounts.createAccount(address(this), manager2);

    // AccountNeg => -100 -> 0
    // newAcc => 0 -> -100
    _transfer(newAcc, accountNeg, tradeAmount);

    uint totalPos1After = option.totalPosition(manager);

    assertEq(totalPos1Before - uint(tradeAmount), totalPos1After);
    assertEq(uint(tradeAmount), option.totalPosition(manager2));
  }

  function testChangeManagerShouldMoveTotalPos() public {
    uint totalPos1Before = option.totalPosition(manager);
    uint totalPos2Before = option.totalPosition(manager2);

    subAccounts.changeManager(accountNeg, manager2, "");

    uint totalPos1After = option.totalPosition(manager);
    uint totalPos2After = option.totalPosition(manager2);

    assertEq(totalPos1After, totalPos1Before - uint(tradeAmount));
    assertEq(totalPos2After, totalPos2Before + uint(tradeAmount));
  }
  
  /// @dev util function to transfer
  function _transfer(uint from, uint to, int amount) internal {
    ISubAccounts.AssetTransfer memory transfer =
      ISubAccounts.AssetTransfer({fromAcc: from, toAcc: to, asset: option, subId: subId, amount: amount, assetData: ""});
    subAccounts.submitTransfer(transfer, "");
  }
}
