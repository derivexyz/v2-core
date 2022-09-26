pragma solidity ^0.8.13;

import "./IAccount.sol";

interface IManager {

  /**
   * @notice triggered when any balance of an account is updated
   * @dev a manager should properly handle final state check on an account
   */
  function handleAdjustment(
    uint accountId,
    address caller, 
    bytes memory data
  ) external;

  /**
   * @notice triggered when a user want to change to a new manager
   * @dev    a manager should only allow migrating to another manager it trusts.
   */
  function handleManagerChange(
    uint accountId, 
    IManager newManager
  ) external;
}