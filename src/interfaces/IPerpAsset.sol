// SPDX-License-Identifier: UNLICENSED
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
    uint128 lastMarkPrice;
    // All funding, not yet settled as cash in Accounts
    int128 funding;
    // Realized pnl, not yet settled as cash in Accounts
    int128 pnl;
    // Last aggregated funding rate applied to this position
    int128 lastAggregatedFundingRate;
    // Timestamp of the last time funding was applied
    uint64 lastFundingPaid;
  }

  /**
   * @notice This function update funding for an account and apply to position detail
   * @param accountId Account Id
   */
  function applyFundingOnAccount(uint accountId) external;

  /**
   * @notice Manager-only function to clear pnl and funding during settlement
   * @dev The manager should then update the cash balance of an account base on the returned netCash variable
   */
  function settleRealizedPNLAndFunding(uint accountId) external returns (int pnl, int funding);

  function getUnsettledAndUnrealizedCash(uint accountId) external view returns (int totalCash);

  function realizePNLWithMark(uint account) external;

  function getIndexPrice() external view returns (uint, uint);

  function getPerpPrice() external view returns (uint, uint);

  function getImpactPrices() external view returns (uint bid, uint ask);

  //////////////////
  //   Events     //
  //////////////////

  event StaticUnderlyingInterestRateUpdated(int128 premium);

  event SpotFeedUpdated(address spotFeed);

  event PerpFeedUpdated(address perpFeed);

  event ImpactFeedsUpdated(address askImpactFeed, address bidImpactFeed);

  event FundingRateUpdated(int aggregatedFundingRate, int fundingRate, uint lastFundingPaidAt);

  event FundingAppliedOnAccount(uint accountId, int funding, int128 aggregatedFundingRate);

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

  /// @dev Invalid static interest rate for base asset
  error PA_InvalidStaticInterestRate();
}
