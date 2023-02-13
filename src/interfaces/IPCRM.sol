// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/interfaces/IBaseManager.sol";

/**
 * @title PartialCollateralRiskManager
 * @author Lyra
 * @notice Risk Manager that controls transfer and margin requirements
 */
interface IPCRM is IBaseManager {
  function getPortfolio(uint accountId) external view returns (Portfolio memory portfolio);

  function executeBid(uint accountId, uint liquidatorId, uint portion, uint cashAmount, uint liquidatorFee) external;

  function getInitialMargin(Portfolio memory portfolio) external view returns (int);

  /// @dev temporary function place holder to return RV = 0
  function getInitialMarginRVZero(Portfolio memory portfolio) external view returns (int);

  function getMaintenanceMargin(Portfolio memory portfolio) external view returns (int);
}
