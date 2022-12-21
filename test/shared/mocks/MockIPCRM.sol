// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../../../src/interfaces/IPCRM.sol";

contract MockIPCRM is IPCRM {
  
  address account;

  constructor(address account) {
    account = account;
  }

  function getSortedHoldings(uint accountId) external virtual view returns (ExpiryHolding[] memory expiryHoldings, int cash) {
    // TODO: filler code
  }

  function executeBid(uint accountId, uint liquidatorId, uint portion, uint cashAmount)
  virtual external
  returns (int finalInitialMargin, ExpiryHolding[] memory, int cash) {
    // TODO: filler code
  }

}