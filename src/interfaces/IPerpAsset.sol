// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import {IAsset} from "./IAsset.sol";
import {IPositionTracking} from "./IPositionTracking.sol";
import {IGlobalSubIdOITracking} from "./IGlobalSubIdOITracking.sol";

/**
 * @title IPerpAsset
 * @notice Interface for a perpetual asset contract that extends the IAsset interface.
 */
interface IPerpAsset is IAsset, IPositionTracking, IGlobalSubIdOITracking {
  struct PositionDetail {
    // Spot price the last time user interact with perp contract
    uint lastMarkPrice;
    // All funding, not yet settled as cash in Accounts
    int funding;
    // Realized pnl, not yet settled as cash in Accounts
    int pnl;
    // Last aggregated funding applied to this position.
    int lastAggregatedFunding;
    // Timestamp of the last time funding was applied
    uint lastFundingPaid;
  }

  /**
   * @notice Manager-only function to clear pnl and funding during settlement
   * @dev The manager should then update the cash balance of an account base on the returned netCash variable
   */
  function settleRealizedPNLAndFunding(uint accountId) external returns (int pnl, int funding);

  function getUnsettledAndUnrealizedCash(uint accountId) external view returns (int totalCash);

  function realizeAccountPNL(uint account) external;

  function getIndexPrice() external view returns (uint, uint);

  function getPerpPrice() external view returns (uint, uint);

  function getImpactPrices() external view returns (uint bid, uint ask);

  //////////////////
  //   Events     //
  //////////////////

  event StaticUnderlyingInterestRateUpdated(int premium);

  event SpotFeedUpdated(address spotFeed);

  event PerpFeedUpdated(address perpFeed);

  event ImpactFeedsUpdated(address askImpactFeed, address bidImpactFeed);

  event RateBoundsUpdated(int maxAbsRatePerHour);

  event ConvergencePeriodUpdated(int fundingConvergencePeriod);

  event Disabled(int indexPrice, int aggregatedFunding);

  event AggregatedFundingUpdated(int aggregatedFundingRate, int fundingRate, uint lastFundingPaidAt);

  event FundingAppliedOnAccount(uint accountId, int funding, int aggregatedFundingRate);

  event PositionSettled(uint indexed account, int pnlChange, int totalPnl, uint perpPrice);

  event PositionCleared(uint indexed account);

  ////////////////
  //   Errors   //
  ////////////////

  /// @dev SubId is not 0
  error PA_InvalidSubId();

  /// @dev Settlement can only be initiated by the manager of the account
  error PA_WrongManager();

  /// @dev Impact prices are invalid: bids higher than ask or negative
  error PA_InvalidImpactPrices();

  error PA_InvalidRateBounds();

  error PA_InvalidConvergencePeriod();

  error PA_InvalidStaticInterestRate();
}
