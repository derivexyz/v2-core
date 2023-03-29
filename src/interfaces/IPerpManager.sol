// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./IManager.sol";
import "./AccountStructs.sol";

interface IPerpManager is AccountStructs, IManager {
  ///////////////
  //   Errors  //
  ///////////////

  /// @dev Caller is not the Account contract
  error PM_NotAccount();

  /// @dev Not whitelist manager
  error PM_NotWhitelistManager();

  error PM_UnsupportedAsset();
  error PM_PortfolioBelowMargin(uint accountId, int margin);
  error PM_InvalidMarginRequirement();

  ///////////////////
  //    Events     //
  ///////////////////

  event AccountSettled(uint accountId, int netCash);

  event MarginRequirementsSet(uint maintenanceMarginRequirement, uint initialMarginRequirement);
}
