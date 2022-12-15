// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/interfaces/IAsset.sol";
import "src/interfaces/IAccount.sol";

contract MoneyPrinterManager is IManager {
  IAccount account;

  constructor(address account_) {
    account = IAccount(account_);
  }

  function handleAdjustment(uint acc, address, AccountStructs.AssetDelta[] memory deltas, bytes memory) public view {}

  function handleManagerChange(uint, IManager) public view {}

  function printMoney(address cash, uint acc, int amount) external {
    account.managerAdjustment(
      AccountStructs.AssetAdjustment({acc: acc, asset: IAsset(cash), subId: 0, amount: amount, assetData: bytes32(0)})
    );
  }

  // add in a function prefixed with test here to prevent coverage from picking it up.
  function test() public {}
}
