pragma solidity ^0.8.13;

import "./AccountStructs.sol";

interface IAbstractManager {
  function handleAdjustment(uint accountId, AccountStructs.AssetBalance[] memory assets, address caller) external;
  function handleManagerChange(uint accountId, IAbstractManager newManager) external;
}