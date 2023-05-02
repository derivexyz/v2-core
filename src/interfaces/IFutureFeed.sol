// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

/**
 * @title IFutureFeed
 * @author Lyra
 * @notice return future feed for 1 asset
 */

interface IFutureFeed {
  /**
   * @notice Gets future price for a particular asset
   * @param expiry Future expiry to query
   */
  function getFuturePrice(uint expiry) external view returns (uint futurePrice);
}
