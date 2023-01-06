// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title PartialCollateralRiskManager
 * @author Lyra
 * @notice Risk Manager that controls transfer and margin requirements
 */
interface IPCRM {
  struct ExpiryHolding {
    uint expiry;
    uint numStrikeHoldings;
    StrikeHolding[] strikes;
  }

  struct StrikeHolding {
    uint64 strike;
    int64 calls;
    int64 puts;
    int64 forwards;
  }

  function getSortedHoldings(uint accountId) external view returns (ExpiryHolding[] memory expiryHoldings, int cash);

  function getGroupedHoldings(uint accountId) external view returns (ExpiryHolding[] memory expiryHoldings);

  function executeBid(uint accountId, uint liquidatorId, uint portion, uint cashAmount)
    external
    returns (int finalInitialMargin, ExpiryHolding[] memory, int cash);

  function getSpot() external view returns (uint spot);

  function getInitialMargin(uint accountId) external returns (int);

  function getMaintenanceMargin(uint accountId) external returns (uint);

  function getAccountValue(uint accountId) external returns (uint);

  function getCashAmount(uint accountId) external view returns (int);
}
