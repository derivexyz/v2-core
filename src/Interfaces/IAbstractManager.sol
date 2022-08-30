pragma solidity ^0.8.13;

import "./AccountStructs.sol";

interface IAbstractManager {
  function handleAdjustment(uint marginAccountId, AccountStructs.AssetBalance[] memory assets, address caller) external;
}