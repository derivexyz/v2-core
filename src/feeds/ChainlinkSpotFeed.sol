// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/utils/math/SafeCast.sol";
import "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "src/interfaces/IChainlinkSpotFeed.sol";
import "src/libraries/ConvertDecimals.sol";
import "src/libraries/SignedDecimalMath.sol";

/**
 * @title ChainlinkSpotFeed
 * @author Lyra
 * @notice Adapter for Chainlink spot aggregator that also does staleness checks
 */
contract ChainlinkSpotFeed is IChainlinkSpotFeed {
  using SafeCast for int;
  using SignedDecimalMath for int;

  // address of chainlink aggregator
  AggregatorV3Interface immutable aggregator;
  // decimal units of returned spot price
  uint8 immutable decimals;

  // todo: potentially be updatable
  uint64 public immutable staleLimit;

  ///@dev Expiry => Settlement price
  mapping(uint => uint) internal settlementPrices;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(AggregatorV3Interface _aggregator, uint64 _staleLimit) {
    aggregator = _aggregator;
    decimals = _aggregator.decimals();
    staleLimit = _staleLimit;
  }

  ////////////////
  // Get Prices //
  ////////////////

  function getSettlementPrice(uint expiry) external view returns (uint) {
    return settlementPrices[expiry];
  }

  /**
   * @dev For now we just return spot price as future price
   */
  function getFuturePrice(uint /*expiry*/ ) external view returns (uint futurePrice) {
    return getSpot();
  }

  /**
   * @notice Gets spot price
   * @return spotPrice 18 decimal price of trading pair.
   */
  function getSpot() public view returns (uint) {
    (uint spotPrice, uint updatedAt) = getSpotAndUpdatedAt();

    if (block.timestamp - updatedAt > staleLimit) {
      revert CF_SpotFeedStale(updatedAt, block.timestamp, staleLimit);
    }

    return spotPrice;
  }

  /**
   * @notice Uses chainlinks `AggregatorV3` oracles to retrieve price.
   *         The price is always converted to an 18 decimal uint.
   * @return spotPrice 18 decimal price of trading pair
   * @return updatedAt Timestamp of update
   */
  function getSpotAndUpdatedAt() public view returns (uint, uint) {
    (uint80 roundId, int answer,, uint updatedAt, uint80 answeredInRound) = aggregator.latestRoundData();

    // Chainlink carries over answer if consensus was not reached.
    // Must get the timestamp of the actual round when answer was recorded.
    if (roundId != answeredInRound) {
      (,,, updatedAt,) = aggregator.getRoundData(answeredInRound);
    }

    // Convert to correct decimals and uint.
    uint spotPrice = ConvertDecimals.convertDecimals(SafeCast.toUint256(answer), decimals, 18);

    return (spotPrice, updatedAt);
  }

  /**
   * @notice Locks-in price which the option settles at for an expiry.
   * @param expiry Timestamp of when the option expires
   */
  function setSettlementPrice(uint expiry) external {
    if (settlementPrices[expiry] != 0) revert CF_SettlementPriceAlreadySet(expiry, settlementPrices[expiry]);
    if (expiry > block.timestamp) revert NotExpired(expiry, block.timestamp);

    settlementPrices[expiry] = getSpot();
    emit SettlementPriceSet(expiry, 0);
  }
}
