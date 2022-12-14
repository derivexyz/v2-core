// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title PartialCollateralRiskManager
 * @author Lyra
 * @notice Risk Manager that controls transfer and margin requirements
 */

interface IPCRM {
  function startAuction(uint accountId) external {}

  function executeBid(uint accountId, uint liquidatorId, uint portion, uint cashAmount) external {}

  function getInitialMargin(ExpiryHolding[] memory expiries) external view returns (int margin) {}

  function getMaintenanceMargin(ExpiryHolding[] memory expiries) external view returns (int margin) {}
}
