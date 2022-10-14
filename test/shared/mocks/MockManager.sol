// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/interfaces/IAsset.sol";
import "src/interfaces/IAccount.sol";
import "forge-std/console2.sol";

contract MockManager is IManager {
  IAccount account;

  bool revertHandleManager;
  bool revertHandleAdjustment;

  constructor(address account_) {
    account = IAccount(account_);
  }

  function handleAdjustment(uint, /*accountId*/ address, AccountStructs.AssetDelta[] memory, bytes memory)
    public
    view
    override
  {
    // for (uint i; i<deltas.length; i++) {
    //   console2.log("i", i, uint(deltas[i].delta));
    // }
    if (revertHandleAdjustment) revert();
  }

  function handleManagerChange(uint, IManager) external view {
    if (revertHandleManager) revert();
  }

  function setRevertHandleManager(bool _revert) external {
    revertHandleManager = _revert;
  }

  function setRevertHandleAdjustment(bool _revert) external {
    revertHandleAdjustment = _revert;
  }
}
