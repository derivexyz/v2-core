// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ISettlementFeed {
  /**
   * @notice Locks-in price which the option settles at for an expiry.
   * @dev Settlement handled by option to simplify multiple managers settling same option
   * @param expiry Timestamp of when the option expires
   */
  function setSettlementPrice(uint expiry) external;

  /**
   * @notice Get settlement value of a specific option.
   * @dev Will return false if option not settled yet.
   * @param subId ID of option.
   * @param balance Amount of option held.
   * @return payout Amount the holder will receive or pay when position is settled
   * @return priceSettled Whether the settlement price of the option has been set.
   */
  function calcSettlementValue(uint subId, int balance) external view returns (int payout, bool priceSettled);

  /**
   * @dev Get settlement price for the underlying asset
   */
  function settlementPrices(uint expiry) external view returns (uint price);

  ////////////
  // Events //
  ////////////

  /// @dev Emitted when spot price for option settlement determined
  event SettlementPriceSet(uint indexed expiry, uint settlementPrice);

  ///////////
  // Error //
  ///////////

  /// @dev revert if settlement price is already set for an expiry
  error SettlementPriceAlreadySet(uint expiry, uint priceSet);

  /// @dev reverts if an option has not reached expiry
  error NotExpired(uint expiry, uint timeNow);
}
