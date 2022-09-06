pragma solidity ^0.8.13;

import "src/interfaces/IAbstractAsset.sol";

interface ISettleable is IAbstractAsset {
  // Are these controlled through the margin account contract or are they separate/users will have to adjust these themselves?
  function calculateSettlement(
    uint subId,
    int balance
  ) external returns (int PnL, bool isSettled);
}
