pragma solidity ^0.8.13;

import "./IAbstractManager.sol";

interface IAbstractAsset {
  function handleAdjustment(
    uint account,
    int preBal,
    int postBal,
    uint96 subId,
    IAbstractManager manager,
    address caller,
    bytes32 data
  ) external returns (int finalBalance);

  function handleManagerChange(
    uint accountId, 
    IAbstractManager oldManager, 
    IAbstractManager newManager
  ) external;
}
