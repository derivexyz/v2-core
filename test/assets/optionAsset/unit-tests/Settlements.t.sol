// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

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

  uint expiry = block.timestamp + 2 weeks;
  uint strike = 1000e18;
  uint callId;
  uint putId;

  function setUp() public {
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    manager = new MockManager(address(account));

    option = new Option(account, address(0));

    callId = option.getSubId(expiry, strike, true);
    putId = option.getSubId(expiry, strike, false);

    accountPos = account.createAccount(address(this), manager);
    accountNeg = account.createAccount(address(this), manager);
    // init these 2 accounts with positive and negative balance
    _transfer(accountNeg, accountPos, tradeAmount);

    accountEmpty = account.createAccount(address(this), manager);
  }

  function testCanSetSettlementPrice() external {}

  function testCannotOptionNotExpired() external {}

  function testCannotSettlePriceAlreadySet() external {}

  function testCalcSettlementValueITMCall() external {}

  function testCalcSettlementValueOTMCall() external {}

  function testCalcSettlementValueITMPut() external {}

  function testCalcSettlementValueOTMPut() external {}

  function testCannotCalcSettlementValueNotExpired() external {}

  function testCannotCalcSettlementValuePriceNotSet() external {}

  /// @dev util function to transfer
  function _transfer(uint from, uint to, int amount) internal {
    AccountStructs.AssetTransfer memory transfer = AccountStructs.AssetTransfer({
      fromAcc: from,
      toAcc: to,
      asset: option,
      subId: callId,
      amount: amount,
      assetData: ""
    });
    account.submitTransfer(transfer, "");
  }
}
