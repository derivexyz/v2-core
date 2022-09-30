pragma solidity ^0.8.13;

interface IManager {

  /**
   * @notice triggered at the end of a tx when any balance of the account is updated
   * @dev a manager should properly check the final stateo of an account
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