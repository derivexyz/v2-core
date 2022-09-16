pragma solidity ^0.8.13;

import "./IManager.sol";

interface IAsset {
  function handleAdjustment(
    IAccount.AssetAdjustment memory adjustment, 
    int preBalance, 
    IManager manager, 
    address caller
  ) external returns (int finalBalance);

  function handleManagerChange(
    uint accountId, 
    IManager oldManager, 
    IManager newManager
  ) external;
}
