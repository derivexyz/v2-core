// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IManager} from "src/interfaces/IManager.sol";

interface IBasicManager is IManager {
  ///@dev Struct for Perp Margin Requirements
  struct PerpMarginRequirements {
    uint mmRequirement;
    uint imRequirement;
  }

  ///@dev Struct for Option Margin Parameters
  struct OptionMarginParameters {
    int baselineOptionIM;
    int baselineOptionMM;
    int minStaticMMRatio;
    int minStaticIMRatio;
  }

  ///////////////
  //   Errors  //
  ///////////////

  /// @dev Caller is not the Accounts contract
  error PM_NotAccounts();

  /// @dev Not whitelist manager
  error PM_NotWhitelistManager();

  error PM_UnsupportedAsset();
  error PM_PortfolioBelowMargin(uint accountId, int margin);
  error PM_InvalidMarginRequirement();

  ///////////////////
  //    Events     //
  ///////////////////

  event PricingModuleSet(address pricingModule);

  event MarginRequirementsSet(uint perpMMRequirement, uint perpIMRequirement);

  event OptionMarginParametersSet(
    int baselineOptionIM, int baselineOptionMM, int minStaticMMRatio, int minStaticIMRatio
  );
}
