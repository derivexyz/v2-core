// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/interfaces/IManager.sol";
import "src/interfaces/IAccount.sol";
import "src/interfaces/ISpotFeeds.sol";
import "src/assets/Lending.sol";
import "src/assets/Option.sol";
import "synthetix/Owned.sol";

/**
 * @title PartialCollateralRiskManager
 * @author Lyra
 * @notice Risk Manager that controls transfer and margin requirements
 */
contract PartialCollateralRiskManager is IManager, Owned {

  ///////////////
  // Variables //
  ///////////////

  /// @dev asset used in all settlements and denominates margin
  IAccount public immutable account;

  /// @dev spotFeeds that determine staleness and return prices
  ISpotFeeds public spotFeeds;

  /// @dev asset used in all settlements and denominates margin
  Lending public immutable lending;

  /// @dev reserved option asset
  Option public immutable option;

  ////////////
  // Events //
  ////////////

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(
    IAccount account_,
    ISpotFeeds spotFeeds_,
    Lending lending_,
    Option option_
  ) Owned() {
    account = account_;
    spotFeeds = spotFeeds_;
    lending = lending_;
    option = option_;
  }


  // Features

  function handleAdjustment(
    uint accountId, 
    address, 
    AccountStructs.AssetDelta[] memory, 
    bytes memory
  ) public override {
    // todo: PCRM check
  }

  function handleManagerChange(uint accountId, IManager newManager) external {}


  ////////////////////////
  // Option Margin Util //
  ////////////////////////
  // todo: make public getters for these

  function _sortOptions(AccountStructs.HeldAsset[] memory heldAssets) internal view {
    // todo: sort out each expiry / strike 
  }

  function _getExpiryValue() internal view {

  }

  function _getStrikeValue() internal view {
    // todo: get call, put, forward values
  }

  //////////////////////
  // Cash Margin Util //
  //////////////////////

  function _getCashValue() internal view {
    // todo: apply interest rate shock
  }

  //////////
  // View //
  //////////

  ////////////
  // Errors //
  ////////////  

}