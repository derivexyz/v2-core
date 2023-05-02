// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "src/interfaces/IAsset.sol";

interface ISettleable is IAsset {
  // Are these controlled through the margin account contract or are they separate/users will have to adjust these themselves?
  function calculateSettlement(uint subId, int balance) external returns (int PnL, bool isSettled);
}
