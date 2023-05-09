// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IManager} from "src/interfaces/IManager.sol";
import {IPerpAsset} from "src/interfaces/IPerpAsset.sol";
import {IOption} from "src/interfaces/IOption.sol";
import {ISingleExpiryPortfolio} from "src/interfaces/ISingleExpiryPortfolio.sol";

interface IBasicManager is IManager {
  enum AssetType {
    NotSet,
    Option,
    Perpetual
  }

  struct AssetDetail {
    bool isWhitelisted;
    AssetType assetType;
    uint8 marketId;
  }

  /**
   * @dev a basic manager portfolio contains up to 5 subAccounts assets
   * each subAccount contains multiple derivative type
   */
  struct BasicManagerPortfolio {
    uint numSubAccounts;
    // @dev each subAccount take care of 1 base asset, for example ETH and BTC.
    BasicManagerSubAccount[] subAccounts;
    int cash;
  }

  struct BasicManagerSubAccount {
    uint marketId;
    // perp position detail
    IPerpAsset perp;
    int perpPosition;
    // option position detail
    IOption option;
    uint numExpiries;
    ExpiryHolding[] expiryHoldings;
  }

  ///@dev contains portfolio struct for single expiry assets
  struct ExpiryHolding {
    uint expiry;
    /// # of strikes with active balances
    uint numStrikesHeld;
    /// array of strike holding details
    ISingleExpiryPortfolio.Strike[] strikes;
  }

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
