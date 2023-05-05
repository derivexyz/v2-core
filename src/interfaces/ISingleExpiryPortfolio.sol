// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface ISingleExpiryPortfolio {
  struct Portfolio {
    /// cash amount or debt
    int cash;
    /// perp amount
    int perp;
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
  }

  /// @dev throw when trying to add an option with different expiry
  error SEP_OnlySingleExpiryPerAccount();
}
