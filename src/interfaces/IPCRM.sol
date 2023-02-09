// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title PartialCollateralRiskManager
 * @author Lyra
 * @notice Risk Manager that controls transfer and margin requirements
 */
interface IPCRM {
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
    uint64 strike;
    int64 calls;
    int64 puts;
    int64 forwards;
  }

  function getPortfolio(uint accountId) external view returns (Portfolio memory portfolio);

  function executeBid(uint accountId, uint liquidatorId, uint portion, uint cashAmount, uint liquidatorFee) external;

  function getInitialMargin(Portfolio memory portfolio) external view returns (int);

  /// @dev temporary function place holder to return RV = 0
  function getInitialMarginRVZero(Portfolio memory portfolio) external view returns (int);

  function getMaintenanceMargin(Portfolio memory portfolio) external view returns (int);
}
