// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../../../src/interfaces/IPCRM.sol";

contract MockIPCRM is IPCRM {
  address account;

  constructor(address _account) {
    account = _account;
  }

  function getSortedHoldings(uint accountId)
    external
    view
    virtual
    returns (ExpiryHolding[] memory expiryHoldings, int cash)
  {
    // TODO: filler code
  }

  function executeBid(uint accountId, uint liquidatorId, uint portion, uint cashAmount)
    external
    virtual
    returns (int finalInitialMargin, ExpiryHolding[] memory, int cash)
  {
    // TODO: filler code
  }

  function getSpot() external view virtual returns (uint spot) {
    // TODO: filler code
    return 1000;
  }

  function getAccountValue(uint accountId) external view virtual returns(uint) {
    // TODO: filler code
  }

  function getInitialMargin(uint accountId) external virtual returns(int) {
    // TODO: filler code
  }

  function getMaintenanceMargin(uint accountId) external returns(uint) {
    // TODO: filler code
  }

  function getGroupedHoldings(uint accountId) external view virtual returns(ExpiryHolding[] memory expiryHoldings) {
    // TODO: filler code
  }
}
