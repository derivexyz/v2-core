// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "src/interfaces/IFutureFeed.sol";
import "src/interfaces/ISettlementFeed.sol";

/**
 * @title IChainlinkSpotFeed
 * @author Lyra
 * @notice Spot feed adapter for Chainlink aggregators.
 *         NOTE: `spotPrice` always assumed to return 18 decimal place uint
 */
interface IChainlinkSpotFeed is IFutureFeed, ISettlementFeed {
  /**
   * @notice Gets spot price
   * @return spotPrice 18 decimal price of trading pair.
   */
  function getSpot() external view returns (uint);

  /**
   * @notice Uses Chainlink aggregator V3 oracle to retrieve price
   * @return spotPrice 18 decimal price of trading pair
   * @return updatedAt Timestamp of update
   */
  function getSpotAndUpdatedAt() external view returns (uint, uint);

  error CF_SettlementPriceAlreadySet(uint expiry, uint priceSet);

  error CF_StaleLimitCannotBeZero();

  error CF_SpotFeedStale(uint updatedAt, uint currentTime, uint staleLimit);
}
