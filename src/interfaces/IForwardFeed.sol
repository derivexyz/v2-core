// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

/**
 * @title IForwardFeed
 * @author Lyra
 * @notice return forward feed for 1 asset
 */

interface IForwardFeed {
  /**
   * @notice Gets forward price for a particular asset
   * @param expiry Forward expiry to query
   */
  function getForwardPrice(uint64 expiry) external view returns (uint forwardPrice, uint confidence);
  function getForwardPricePortions(uint64 expiry)
    external
    view
    returns (uint forwardFixedPortion, uint forwardVariablePortion, uint confidence);
}
