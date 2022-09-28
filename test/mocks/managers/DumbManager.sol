pragma solidity ^0.8.13;

import "src/interfaces/IAsset.sol";
import "src/interfaces/IAccount.sol";

contract DumbManager is IManager {
  
  IAccount account;

  bool revertHandleManager;
  bool revertHandleAdjustment;

  constructor(address account_) {
    account = IAccount(account_);
  }

  function handleAdjustment(uint accountId, address, bytes memory) public override {
    if(revertHandleAdjustment) revert();
  }

  function handleManagerChange(uint, IManager) external { 
    if(revertHandleManager) revert();
  }

  function setRevertHandleManager(bool _revert) external {
    revertHandleManager = _revert;
  }

  function setRevertHandleAdjustment(bool _revert) external {
    revertHandleAdjustment = _revert;
  }
}
