// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ISettlementFeed {
  
  /**
   * @notice Locks-in price at which option settles.
   * @dev Settlement handled by option to simplify multiple managers settling same option
   * @param subId ID of option
   */
  function setSettlementPrice(uint subId) external;

  /**
   * @notice Get settlement value of a specific option. Will return false if option not settled yet.
   * @param subId ID of option.
   * @param balance Amount of option held.
   * @return payout Amount the holder will receive or pay when position is settled
   * @return priceSettled Whether the settlement price of the option has been set.
   */
  function calcSettlementValue(uint sudId, int balance) external view returns (int payout, bool priceSettled);

  ////////////
  // Events //
  ////////////

  /// @dev Emitted when spot price for option settlement determined
  event SettlementPriceSet(uint indexed subId, uint settlementPrice);
}