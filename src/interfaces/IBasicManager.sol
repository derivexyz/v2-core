// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IManager} from "src/interfaces/IManager.sol";
import {IPerpAsset} from "src/interfaces/IPerpAsset.sol";
import {IOption} from "src/interfaces/IOption.sol";

interface IBasicManager {
  enum AssetType {
    NotSet,
    Option,
    Perpetual,
    Base
  }

  struct AssetDetail {
    bool isWhitelisted;
    AssetType assetType;
    uint8 marketId;
  }

  /**
   * @dev a basic manager portfolio contains up to 5 marketHoldings assets
   * each marketHolding contains multiple derivative type
   */
  struct BasicManagerPortfolio {
    // @dev each marketHolding take care of 1 base asset, for example ETH and BTC.
    MarketHolding[] marketHoldings;
    int cash;
  }

  struct MarketHolding {
    uint8 marketId;
    // base position: doesn't contribute to margin, but increase total portfolio mark to market
    int basePosition;
    // perp position detail
    IPerpAsset perp;
    int perpPosition;
    // option position detail
    IOption option;
    ExpiryHolding[] expiryHoldings;
    /// sum of all short positions. used to increase margin requirement if USDC depeg. Should be positive
    int totalShortPositions;
  }

  ///@dev contains portfolio struct for single expiry assets
  struct ExpiryHolding {
    /// expiry timestamp
    uint expiry;
    /// array of strike holding details
    Option[] options;
    /// sum of all call positions, used to determine if portfolio max loss is bounded
    int netCalls;
    /// temporary variable to count how many options is used
    uint numOptions;
    /// total short position size. should be positive
    int totalShortPositions;
  }
  /// temporary variable to keep track of the lowest confidence level of all oracles
  // uint minConfidence;

  struct Option {
    uint strike;
    int balance;
    bool isCall;
  }

  ///@dev Struct for Perp Margin Requirements
  struct PerpMarginRequirements {
    uint mmRequirement;
    uint imRequirement;
  }

  ///@dev Struct for Option Margin Parameters
  struct OptionMarginParameters {
    int scOffset1;
    int scOffset2;
    int mmSCSpot;
    int mmSPSpot;
    int mmSPMtm;
    int unpairedScale;
  }

  struct DepegParams {
    int128 threshold;
    int128 depegFactor;
  }

  struct OracleContingencyParams {
    uint64 perpThreshold;
    uint64 optionThreshold;
    int64 OCFactor;
  }

  ///////////////
  //   Errors  //
  ///////////////

  /// @dev Caller is not the Accounts contract
  error BM_NotAccounts();

  /// @dev Not whitelist manager
  error BM_NotWhitelistManager();

  /// @dev Not supported asset
  error BM_UnsupportedAsset();

  /// @dev Account is under water, need more cash
  error BM_PortfolioBelowMargin(uint accountId, int margin);

  /// @dev Invalid Parameters for perp margin requirements
  error BM_InvalidMarginRequirement();

  /// @dev Forward Price for an asset is 0
  error BM_NoForwardPrice();

  /// @dev Invalid depeg parameters
  error BM_InvalidDepegParams();

  /// @dev Invalid Oracle contingency params
  error BM_InvalidOracleContingencyParams();

  /// @dev No negative cash
  error BM_NoNegativeCash();

  ///////////////////
  //    Events     //
  ///////////////////

  event AssetWhitelisted(address asset, uint8 marketId, AssetType assetType);

  event OraclesSet(
    uint8 marketId,
    address spotOracle,
    address perpOracle,
    address forwardOracle,
    address settlementOracle,
    address volFeed
  );

  event PricingModuleSet(uint8 marketId, address pricingModule);

  event MarginRequirementsSet(uint8 marketId, uint perpMMRequirement, uint perpIMRequirement);

  event OptionMarginParametersSet(
    uint8 marketId, int scOffset1, int scOffset2, int mmSCSpot, int mmSPSpot, int mmSPMtm, int unpairedScale
  );

  event DepegParametersSet(int128 threshold, int128 depegFactor);

  event OracleContingencySet(uint64 prepThreshold, uint64 optionThreshold, int128 ocFactor);

  event StableFeedUpdated(address stableFeed);
}
