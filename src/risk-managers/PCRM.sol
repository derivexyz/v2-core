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
contract PCRM is IManager, Owned {

  enum MarginType {
    INITIAL,
    MAINTENANCE
  }

  struct ExpiryHolding {
    uint expiry;
    StrikeHolding[] strikes;
  }

  struct StrikeHolding {
    uint64 strike;
    int64 calls;
    int64 puts;
    int64 forwards;
  }

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

  /// @dev dutch auction contract used to auction liquidatable accounts
  address public immutable dutchAuction;

  ////////////
  // Events //
  ////////////

  ///////////////
  // Modifiers //
  ///////////////

  modifier onlyAuction() {
    if (msg.sender != dutchAuction) {
      revert PCRM_OnlyAuction(msg.sender, dutchAuction);
    }
    _;
  }

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(
    address account_,
    address spotFeeds_,
    address lending_,
    address option_
  ) Owned() {
    account = IAccount(account_);
    spotFeeds = ISpotFeeds(spotFeeds_);
    lending = Lending(lending_);
    option = Option(option_);
    dutchAuction = address(0); // todo: add once dutch auction interface present
  }


  ///////////////////
  // Account Hooks //
  /////////////////// 

  function handleAdjustment(
    uint accountId, 
    address, 
    AccountStructs.AssetDelta[] memory, 
    bytes memory
  ) public view override {
    // todo: whitelist check

    // PCRM calculations
    ExpiryHolding[] memory expiries = _sortOptions(account.getAccountBalances(accountId));
    _calcMargin(expiries, MarginType.INITIAL);
  }

  function handleManagerChange(uint accountId, IManager newManager) external {
    // todo: nextManager whitelist check
  }

  //////////////////
  // Liquidations //
  ////////////////// 

  function startAuction(uint accountId) external {
    // todo: check that account is liquidatable / freeze account / call out to auction contract
  }

  function executeBid(uint accountId, uint liquidatorId, uint portion, uint cashAmount) external onlyAuction() {
    // todo: this would be only dutch auction contract
  }

  /////////////////
  // Margin Math //
  ///////////////// 

  function _calcMargin(
    ExpiryHolding[] memory expiries, 
    MarginType marginType
  ) internal view returns (int margin) {
    for (uint i; i < expiries.length; i++) {
      margin += _calcExpiryValue(expiries[i], marginType);
    }

    margin += _calcCashValue(marginType);
  }

  
  // Option Margin Math

  function _calcExpiryValue(
    ExpiryHolding memory expiry, 
    MarginType marginType
  ) internal view returns (int expiryValue) {
    expiryValue;
    for (uint i; i < expiry.strikes.length; i++) {
      expiryValue += _calcStrikeValue(expiry.strikes[i], marginType);
    }
  }

  function _calcStrikeValue(
    StrikeHolding memory strikeHoldings, 
    MarginType marginType
  ) internal view returns (int strikeValue) {
    // todo: get call, put, forward values
  }
  
  // Cash Margin Math
  
  function _calcCashValue(MarginType marginType) internal view returns (int cashValue) {
    // todo: apply interest rate shock
  }

  //////////
  // Util //
  //////////

  function _sortOptions(
    AccountStructs.AssetBalance[] memory assets
  ) internal view returns (ExpiryHolding[] memory expiryHoldings) {
    // todo: sort out each expiry / strike 
    // todo: ignore the lendingAsset
    // todo: add limit to # of expiries and # of options
  }

  //////////
  // View //
  //////////

  function getInitialMargin(ExpiryHolding[] memory expiries) external view returns (int margin) {
    return _calcMargin(expiries, MarginType.INITIAL);
  }

  function getMaintenanceMargin(ExpiryHolding[] memory expiries) external view returns (int margin) {
    return _calcMargin(expiries, MarginType.MAINTENANCE);
  }

  ////////////
  // Errors //
  ////////////  

  error PCRM_OnlyAuction(address sender, address auction);

}