pragma solidity ^0.8.13;

import "src/interfaces/IAsset.sol";
import "src/interfaces/IAccount.sol";

contract DumbManager is IManager {
  
  IAccount account;

  constructor(address account_) {
    account = IAccount(account_);
  }

  function handleAdjustment(uint accountId, address, bytes memory) public override {}


  function handleManagerChange(uint, IManager) external {}

}
