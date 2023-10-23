// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IAsset} from "./IAsset.sol";
import {IPerpAsset} from "./IPerpAsset.sol";
import {IBaseManager} from "./IBaseManager.sol";
import {IOptionAsset} from "./IOptionAsset.sol";

interface IStandardManager is IBaseManager {
  enum AssetType {
    NotSet,
    Option,
    Perpetual,
    Base
  }

  struct AssetDetail {
    bool isWhitelisted;
    AssetType assetType;
    uint marketId;
  }

  /**
   * @dev a standard manager portfolio contains multiple marketHoldings assets, each marketHolding contains multiple derivative type
   */
  struct StandardManagerPortfolio {
    // @dev each marketHolding take care of 1 base asset, for example ETH and BTC.
    MarketHolding[] marketHoldings;
    int cash;
  }

  struct MarketHolding {
    uint marketId;
    /// base position: doesn't contribute to margin, but increase total portfolio mark to market
    uint basePosition;
    /// perp position detail
    IPerpAsset perp;
    int perpPosition;
    /// option position detail
    IOptionAsset option;
    ExpiryHolding[] expiryHoldings;
    // sum of all short positions and abs(perps) for the market.
    // used to increase margin requirement if stable price depegs.
    uint depegPenaltyPos;
  }

  /// @dev contains portfolio struct for single expiry assets
  struct ExpiryHolding {
    /// array of option hold in this expiry
    Option[] options;
    /// expiry timestamp
    uint expiry;
    /// sum of all call positions, used to determine if portfolio max loss is bounded
    int netCalls;
    /// temporary variable to count how many options is used
    uint numOptions;
    /// total short position size. should be positive
    uint totalShortPositions;
  }

  struct Option {
    uint strike;
    int balance;
    bool isCall;
  }

  /// @dev Struct for Perp Margin Requirements
  struct PerpMarginRequirements {
    /// @dev minimum amount of spot required as maintenance margin for each perp position
    uint mmPerpReq;
    /// @dev minimum amount of spot required as initial margin for each perp position
    uint imPerpReq;
  }

  /// @dev Struct for Option Margin Parameters
  struct OptionMarginParams {
    /// @dev Percentage of spot to add to initial margin if option is ITM. Decreases as option becomes more OTM.
    uint maxSpotReq;
    /// @dev Minimum amount of spot price to add as initial margin.
    uint minSpotReq;
    /// @dev Minimum amount of spot price to add as maintenance margin.
    uint mmCallSpotReq;
    /// @dev Minimum amount of spot to add for maintenance margin
    uint mmPutSpotReq;
    /// @dev Minimum amount of mtm to add for maintenance margin for puts
    uint MMPutMtMReq;
    /// @dev Scaler applied to forward by amount if max loss is unbounded, when calculating IM
    uint unpairedIMScale;
    /// @dev Scaler applied to forward by amount if max loss is unbounded, when calculating MM
    uint unpairedMMScale;
    /// @dev Scale the MM for a put as minimum of IM
    uint mmOffsetScale;
  }

  struct DepegParams {
    uint threshold;
    uint depegFactor;
  }

  struct OracleContingencyParams {
    uint perpThreshold;
    uint optionThreshold;
    uint baseThreshold;
    uint OCFactor;
  }

  function assetDetails(IAsset asset) external view returns (AssetDetail memory);

  ///////////////
  //   Errors  //
  ///////////////

  /// @dev Market is not created yet
  error SRM_MarketNotCreated();

  /// @dev One asset cannot be assign to multiple markets
  error SRM_CannotSetSameAsset();

  /// @dev Caller is not the Accounts contract
  error SRM_NotAccounts();

  /// @dev Not whitelist manager
  error SRM_NotWhitelistManager();

  /// @dev Not supported asset
  error SRM_UnsupportedAsset();

  /// @dev Too many assets in one subaccount
  error SRM_TooManyAssets();

  /// @dev Account is under water, need more cash
  error SRM_PortfolioBelowMargin();

  /// @dev Invalid Parameters for perp margin requirements
  error SRM_InvalidPerpMarginParams();

  error SRM_InvalidOptionMarginParams();

  /// @dev Forward Price for an asset is 0
  error SRM_NoForwardPrice();

  /// @dev Invalid depeg parameters
  error SRM_InvalidDepegParams();

  /// @dev Invalid Oracle contingency params
  error SRM_InvalidOracleContingencyParams();

  /// @dev Invalid base asset margin discount factor
  error SRM_InvalidBaseDiscountFactor();

  /// @dev No negative cash
  error SRM_NoNegativeCash();

  ///////////////////
  //    Events     //
  ///////////////////

  event MarketCreated(uint marketId, string marketName);

  event AssetWhitelisted(address asset, uint marketId, AssetType assetType);

  event OraclesSet(uint marketId, address spotOracle, address forwardOracle, address volFeed);

  event PricingModuleSet(uint marketId, address pricingModule);

  event PerpMarginRequirementsSet(uint marketId, uint perpMMRequirement, uint perpIMRequirement);

  event OptionMarginParamsSet(
    uint marketId,
    uint maxSpotReq,
    uint minSpotReq,
    uint mmCallSpotReq,
    uint mmPutSpotReq,
    uint MMPutMtMReq,
    uint unpairedIMScale,
    uint unpairedMMScale,
    uint mmOffsetScale
  );

  event BaseMarginDiscountFactorSet(uint marketId, uint baseMarginDiscountFactor);

  event DepegParametersSet(uint threshold, uint depegFactor);

  event OracleContingencySet(uint prepThreshold, uint optionThreshold, uint baseThreshold, uint OCFactor);

  event StableFeedUpdated(address stableFeed);

  event BorrowingEnabled(bool borrowingEnabled);
}
