// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "../../../shared/mocks/MockERC20.sol";
import "../../../shared/mocks/MockManager.sol";
import "../../../../src/assets/Option.sol";
import "../../../../src/Accounts.sol";

/**
 * @dev testing open interest before and after
 * asset transfers
 * single side adjustments
 */
contract UNIT_OptionAssetOITest is Test {
  Option option;
  MockManager manager;
  Accounts account;

  int tradeAmount = 100e18;
  uint accountPos; // balance: 100
  uint accountNeg; // balance: -100
  uint accountEmpty; // balance: 0

  uint subId = 99999;

  function setUp() public {
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    manager = new MockManager(address(account));

    option = new Option(account, address(0));
    option.setWhitelistManager(address(manager), true);

    accountPos = account.createAccount(address(this), manager);
    accountNeg = account.createAccount(address(this), manager);
    // init these 2 accounts with positive and negative balance
    _transfer(accountNeg, accountPos, tradeAmount);

    accountEmpty = account.createAccount(address(this), manager);
  }

  /* --------------------- *
   |      Transfers        *
   * --------------------- */

  function testFirstTranferIncreaseOI() public {
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
    // AccountNeg => 0 -> -100
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

  /// @dev util functino to transfer
  function _transfer(uint from, uint to, int amount) internal {
    IAccounts.AssetTransfer memory transfer =
      IAccounts.AssetTransfer({fromAcc: from, toAcc: to, asset: option, subId: subId, amount: amount, assetData: ""});
    account.submitTransfer(transfer, "");
  }
}
