// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/interfaces/ISettlementFeed.sol";
import "src/interfaces/IFutureFeed.sol";

/**
 * @notice interface of feed contract we launch v2.0 with.
 * @dev    The same contract will be used as both settlement feed and future feed
 */
interface ITokenFeedV2 is ISettlementFeed, IFutureFeed {
  /**
   * @notice Locks-in price for an asset for an expiry.
   * @param expiry Timestamp of when the expires
   */
  function setSettlementPrice(uint expiry) external;

  ///////////
  // Error //
  ///////////

  /// @dev revert if settlement price is already set for an expiry
  error SettlementPriceAlreadySet(uint expiry, uint priceSet);
}
