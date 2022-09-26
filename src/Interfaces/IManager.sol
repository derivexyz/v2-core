pragma solidity ^0.8.13;

import "./IAccount.sol";

interface IManager {
  function handleAdjustment(
    uint accountId,
    address caller, 
    bytes memory data
  ) external;

  function handleManagerChange(
    uint accountId, 
    IManager newManager
  ) external;
}