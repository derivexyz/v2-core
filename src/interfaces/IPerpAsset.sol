// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./IAsset.sol";

/**
 * @title IPerpAsset
 * @notice Interface for a perpetual asset contract that extends the IAsset interface.
 */
interface IPerpAsset is IAsset {
  struct PositionDetail {
    // Price that the position was opened at
    uint entryPrice;
    // All funding, not yet settled as cash in Accounts
    int funding;
    // Realized pnl, not yet settled as cash in Accounts
    int pnl;
    // Last aggregated funding rate applied to this position
    int lastAggregatedFundingRate;
    // Timestamp of the last time funding was applied
    uint lastFundingPaid;
  }

  /**
   * @notice This function update funding for an account and apply to position detail
   * @param accountId Account Id
   */
  function applyFundingOnAccount(uint accountId) external;

  /**
   * @dev manager-only function to clear pnl and funding during settlement
   */
  function settleRealizedPNLAndFunding(uint accountId) external returns (int netCash);

  //////////////////
  //   Events     //
  //////////////////

  event FundingRateUpdated(int premium);

  event StaticUnderlyingInterestRateUpdated(int128 premium);

  event FundingRateOracleUpdated(address oracle);

  event SpotFeedUpdated(address spotFeed);

  ////////////////
  //   Errors   //
  ////////////////

  /// @dev Caller is not the Account contract
  error PA_NotAccount();

  /// @dev Caller is not the liquidation module
  error PA_NotLiquidationModule();

  /// @dev Revert when user trying to upgrade to an unknown manager
  error PA_UnknownManager();

  /// @dev Settlement can only be initiated by the manager of the account
  error PA_WrongManager();

  /// @dev Caller is not the owner of the account
  error PA_OnlyAccountOwner();

  /// @dev Impact price must be positive
  error PA_ImpactPriceMustBePositive();

  /// @dev Invalid static interest rate for base asset
  error PA_InvalidStaticInterestRate();

  /// @dev Caller is not the impact price oracle address
  error PA_OnlyImpactPriceOracle();
}
