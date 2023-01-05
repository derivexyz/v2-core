// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/interfaces/IAsset.sol";
import "src/interfaces/ISpotFeeds.sol";
import "synthetix/Owned.sol";
import "src/libraries/OptionEncoding.sol";

/**
 * @title Option
 * @author Lyra
 * @notice Option asset that defines subIds, value and settlement
 */
contract Option is IAsset, Owned {
  ///////////////
  // Variables //
  ///////////////

  ////////////
  // Events //
  ////////////

  /// @dev Emitted when spot price for option settlement determined
  event SettlementPriceSet(uint indexed subId, uint settlementPrice);

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  ///////////////
  // Transfers //
  ///////////////

  function handleAdjustment(
    AccountStructs.AssetAdjustment memory adjustment,
    int preBalance,
    IManager, /*manager*/
    address /*caller*/
  ) external pure returns (int finalBalance, bool needAllowance) {
    // todo: check whitelist

    // todo: make sure valid subId
    return (preBalance + adjustment.amount, adjustment.amount < 0);
  }

  function handleManagerChange(uint accountId, IManager newManager) external {
    // todo: check whitelist
  }

  ////////////////
  // Settlement //
  ////////////////

  /**
   * @notice Locks-in price at which option settles.
   * @dev Settlement handled by option to simplify multiple managers settling same option
   * @param subId ID of option
   */
  function setSettlementPrice(uint subId) external {
    // todo: integrate with settlementFeeds
    emit SettlementPriceSet(subId, 0);
  }

  //////////
  // View //
  //////////

  /**
   * @notice Decode subId into expiry, strike and whether option is call or put
   * @param subId ID of option.
   */
  function getOptionDetails(uint96 subId) external pure returns (uint expiry, uint strike, bool isCall) {
    return OptionEncoding.fromSubId(subId);
  }

  /**
   * @notice Encode subId into expiry, strike and whether option is call or put
   * @param expiry Expiration of option in epoch time.
   * @param strike Strike price of option.
   * @param isCall Whether option is a call or put
   */
  function getSubId(uint expiry, uint strike, bool isCall) external pure returns (uint96 subId) {
    return OptionEncoding.toSubId(expiry, strike, isCall);
  }

  /**
   * @notice Get settlement value of a specific option. Will return false if option not settled yet.
   * @param subId ID of option.
   * @param balance Amount of option held.
   * @return pnl Amount the holder will receive or pay when position is settled
   * @return priceSettled Whether the settlement price of the option has been set.
   */
  function calcSettlementValue(uint subId, int balance) external view returns (int pnl, bool priceSettled) {
    // todo: basic pnl
  }

  ////////////
  // Errors //
  ////////////
}
