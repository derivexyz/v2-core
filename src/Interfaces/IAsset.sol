pragma solidity ^0.8.13;

import "./IManager.sol";

interface IAsset {
  function handleAdjustment(
    uint account,
    int preBal,
    int amount,
    uint96 subId,
    IManager manager,
    address caller,
    bytes32 data
  ) external returns (int finalBalance);

  function handleManagerChange(
    uint accountId, 
    IManager oldManager, 
    IManager newManager
  ) external;
}
