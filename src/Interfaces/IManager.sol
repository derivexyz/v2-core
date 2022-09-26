pragma solidity ^0.8.13;

import "./IAccount.sol";

interface IManager {
  function handleAdjustment(
    uint accountId, 
    // TODO: should this not be forced?
    IAccount.AssetBalance[] memory assets, 
    address caller, 
    bytes memory data
  ) external;

  function handleManagerChange(
    uint accountId, 
    IManager newManager
  ) external;
}