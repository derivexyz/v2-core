// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IBaseManager {
  /////////////
  // Structs //
  /////////////

  function feeCharged(uint tradeId, uint account) external view returns (uint);

  struct Portfolio {
    /// cash amount or debt
    int cash;
    /// timestamp of expiry for all strike holdings
    uint expiry;
    /// # of strikes with active balances
    uint numStrikesHeld;
    /// array of strike holding details
    Strike[] strikes;
  }

  struct Strike {
    /// strike price of held options
    uint strike;
    /// number of calls held
    int calls;
    /// number of puts held
    int puts;
    /// number of forwards held
    int forwards;
  }
}
