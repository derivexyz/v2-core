// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/interfaces/IAsset.sol";
import "src/interfaces/IAccount.sol";
import "src/interfaces/AccountStructs.sol";

// Dumb manager for test bench mark
contract DumbManager is IManager {
  
  IAccount account;

  bool revertHandleManager;
  bool revertHandleAdjustment;

  constructor(address account_) {
    account = IAccount(account_);
  }

  function handleAdjustment(uint /*accountId*/, address, bytes memory) public view override {
    if(revertHandleAdjustment) revert();
  }

  function handleManagerChange(uint, IManager) external view { 
    if(revertHandleManager) revert();
  }

  /// @dev used to estimate gas cost by setting balances to 0
  function clearBalance(uint accountId, AccountStructs.HeldAsset[] memory assetsToSettle) external {
    uint assetLen = assetsToSettle.length;
    for (uint i; i < assetLen; i++) {
      int balance = account.getBalance(accountId, assetsToSettle[i].asset, assetsToSettle[i].subId);
      account.managerAdjustment(
        AccountStructs.AssetAdjustment({
          acc: accountId,
          asset: assetsToSettle[i].asset,
          subId: assetsToSettle[i].subId,
          amount: -balance, // set back to zero
          assetData: bytes32(0)
        })
      );
    }
  }

  function setRevertHandleManager(bool _revert) external {
    revertHandleManager = _revert;
  }

  function setRevertHandleAdjustment(bool _revert) external {
    revertHandleAdjustment = _revert;
  }
}
