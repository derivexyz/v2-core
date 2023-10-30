// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface ISettlementFeed {
  /**
   * @dev Get settlement price for the underlying asset
   */
  function getSettlementPrice(uint64 expiry) external view returns (bool settled, uint price);

  ////////////
  // Events //
  ////////////

  /// @dev Emitted when spot price for option settlement determined
  event SettlementPriceSet(uint indexed expiry, uint settlementPrice);

  ////////////
  // Errors //
  ////////////

  /// @dev reverts if an expiry is not reached yet
  error NotExpired(uint expiry, uint timeNow);
}
