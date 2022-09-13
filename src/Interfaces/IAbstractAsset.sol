pragma solidity ^0.8.13;

import "./IAbstractManager.sol";

interface IAbstractAsset {
  // Are these controlled through the margin account contract or are they separate/users will have to adjust these themselves?
  function handleAdjustment(
    uint account,
    int preBal,
    int postBal,
    uint subId,
    IAbstractManager manager,
    address caller,
    bytes memory data
  ) external;

  function handleManagerChange(
    uint accountId, 
    IAbstractManager oldManager, 
    IAbstractManager newManager,
    bytes memory data
  ) external;
}
