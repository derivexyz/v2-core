// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/interfaces/IAsset.sol";
import "src/interfaces/IAccount.sol";

contract MockManager is IManager {
  IAccount account;

  bool revertHandleManager;
  bool revertHandleAdjustment;

  constructor(address account_) {
    account = IAccount(account_);
  }

  function handleAdjustment(uint, /*accountId*/ address, bytes memory) public view virtual {
    if (revertHandleAdjustment) revert();
  }

  function handleManagerChange(uint, IManager) public view virtual {
    if (revertHandleManager) revert();
  }

  function setRevertHandleManager(bool _revert) external {
    revertHandleManager = _revert;
  }

  function setRevertHandleAdjustment(bool _revert) external {
    revertHandleAdjustment = _revert;
  }
}
