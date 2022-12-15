// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/interfaces/IAsset.sol";
import "src/interfaces/ISpotFeeds.sol";
import "synthetix/Owned.sol";

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

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  ///////////////
  // Transfers //
  ///////////////

  function handleAdjustment(
    AccountStructs.AssetAdjustment memory adjustment,
    int preBalance,
    IManager manager,
    address caller
  ) external returns (int finalBalance, bool needAllowance) {
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
  }

  //////////
  // View //
  //////////

  /**
   * @notice Decode subId into expiry, strike and whether option is call or put
   * @param subId ID of option.
   */
  function getOptionDetails(uint96 subId) external view returns (uint expiry, uint strike, bool isCall) {
    // todo: uint96 encoding library
  }

  /**
   * @notice Encode subId into expiry, strike and whether option is call or put
   * @param expiry Expiration of option in epoch time.
   * @param strike Strike price of option.
   * @param isCall Whether option is a call or put
   */
  function getSubId(uint32 expiry, uint64 strike, bool isCall) external view returns (uint96 subId) {
    // todo: uint96 encoding library
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
