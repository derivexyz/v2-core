pragma solidity ^0.8.13;

import "./MarginStructs.sol";

interface IAbstractManager {
  function handleAdjustment(uint marginAccountId, MarginStructs.AssetBalance[] memory assets, address caller) external;
}