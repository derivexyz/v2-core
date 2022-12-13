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
  }

  /**
   * @notice triggered when a user wants to migrate an account to a new manager
   * @dev an asset can block a migration to a un-trusted manager, e.g. a manager that does not take care of liquidation
   */
  function handleManagerChange(uint accountId, IManager newManager) external {
    // todo: check whitelist
  }


  ////////////////
  // Settlement //
  ////////////////

  function setSettlementPrice(uint subId) external {
    // todo: integrate with spotFeeds
  }

  //////////
  // View //
  //////////

  function getOptionDetails(uint96 subId) external view returns (uint expiry, uint strike, bool isCall) {
    // todo: uint96 encoding library 
  }

  function getSubId(uint32 expiry, uint64 strike, bool isCall) external view returns (uint96 subId) {
    // todo: uint96 encoding library 
  }

  function calcSettlementValue(uint subId, int balance) external view returns (int pnl, bool priceSettled) {
    // todo: basic pnl
  }

  ////////////
  // Errors //
  ////////////  

}