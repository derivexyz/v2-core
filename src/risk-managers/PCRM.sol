// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/interfaces/IManager.sol";
import "src/interfaces/IAccount.sol";
import "src/interfaces/ISpotFeeds.sol";
import "src/interfaces/IDutchAuction.sol";
import "src/assets/Lending.sol";
import "src/assets/Option.sol";
import "src/libraries/OptionEncoding.sol";
import "src/libraries/PCRMSorting.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "synthetix/Owned.sol";

/**
 * @title PartialCollateralRiskManager
 * @author Lyra
 * @notice Risk Manager that controls transfer and margin requirements
 */
contract PCRM is IManager, Owned {
  /**
   * INITIAL: margin required for trade to pass
   * MAINTENANCE: margin required to prevent liquidation
   */
  enum MarginType {
    INITIAL,
    MAINTENANCE
  }

  struct ExpiryHolding {
    /// timestamp of expiry for all strike holdings
    uint expiry;
    /// array of strike holding details
    StrikeHolding[] strikes;
  }

  struct StrikeHolding {
    /// strike price of held options
    uint strike;
    /// number of calls held
    int calls;
    /// number of puts held
    int puts;
    /// number of forwards held
    int forwards;
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
  IDutchAuction public immutable dutchAuction;

  ////////////
  // Events //
  ////////////

  ///////////////
  // Modifiers //
  ///////////////

  modifier onlyAuction() {
    if (msg.sender != address(dutchAuction)) {
      revert PCRM_OnlyAuction(msg.sender, address(dutchAuction));
    }
    _;
  }

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(address account_, address spotFeeds_, address lending_, address option_, address auction_) Owned() {
    account = IAccount(account_);
    spotFeeds = ISpotFeeds(spotFeeds_);
    lending = Lending(lending_);
    option = Option(option_);
    dutchAuction = IDutchAuction(auction_);
  }

  ///////////////////
  // Account Hooks //
  ///////////////////

  /**
   * @notice Ensures asset is valid and initial margin is met.
   * @param accountId Account for which to check trade.
   */
  function handleAdjustment(uint accountId, address, AccountStructs.AssetDelta[] memory, bytes memory)
    public
    view
    override
  {
    // todo [Josh]: whitelist check

    // PCRM calculations
    ExpiryHolding[] memory expiries = _sortHoldings(account.getAccountBalances(accountId));
    _calcMargin(expiries, MarginType.INITIAL);
  }

  /**
   * @notice Ensures new manager is valid.
   * @param accountId Account for which to check trade.
   * @param newManager IManager to change account to.
   */
  function handleManagerChange(uint accountId, IManager newManager) external {
    // todo [Josh]: nextManager whitelist check
  }

  //////////////////
  // Liquidations //
  //////////////////

  /**
   * @notice Confirm account is liquidatable and puts up for dutch auction.
   * @param accountId Account for which to check trade.
   */
  function checkAndStartLiquidation(uint accountId) external {
    dutchAuction.startAuction(accountId);
    // todo [Cameron / dom]: check that account is liquidatable / freeze account / call out to auction contract
  }

  /**
   * @notice Transfers portion of account to the liquidator.
   *         Transfers cash to the liquidated account.
   * @dev Auction contract can decide to either:
   *      - revert / process bid
   *      - continue / complete auction
   * @param accountId ID of account which is being liquidated.
   * @param liquidatorId Liquidator account ID.
   * @param portion Portion of account that is requested to be liquidated.
   * @param cashAmount Cash amount liquidator is offering for portion of account.
   * @return postExecutionInitialMargin InitialMargin of account after portion is liquidated.
   * @return expiryHoldings Sorted array of option holdings used to recompute new auction bounds
   * @return cash Amount of cash held or borrowed in account
   */
  function executeBid(uint accountId, uint liquidatorId, uint portion, uint cashAmount)
    external
    onlyAuction
    returns (int postExecutionInitialMargin, ExpiryHolding[] memory, int cash)
  {
    // todo [Cameron / Dom]: this would be only dutch auction contract
  }

  /////////////////
  // Margin Math //
  /////////////////

  /**
   * @notice Calculate the initial or maintenance margin of account.
   *         A negative value means the account is X amount over the required margin.
   * @param expiries Sorted array of option holdings.
   * @param marginType Initial or maintenance margin.
   * @return margin Amount by which account is over or under the required margin.
   */
  function _calcMargin(ExpiryHolding[] memory expiries, MarginType marginType) internal view returns (int margin) {
    for (uint i; i < expiries.length; i++) {
      margin += _calcExpiryValue(expiries[i], marginType);
    }

    margin += _calcCashValue(marginType);
  }

  // Option Margin Math

  /**
   * @notice Calculate the discounted value of option holdings in a specific expiry.
   * @param expiry All option holdings within an expiry.
   * @param marginType Initial or maintenance margin.
   * @return expiryValue Value of assets or debt of options in a given expiry.
   */
  function _calcExpiryValue(ExpiryHolding memory expiry, MarginType marginType) internal view returns (int expiryValue) {
    expiryValue;
    for (uint i; i < expiry.strikes.length; i++) {
      expiryValue += _calcStrikeValue(expiry.strikes[i], marginType);
    }
  }

  /**
   * @notice Calculate the discounted value of option holdings in a specific strike.
   * @param strikeHoldings All option holdings of the same strike.
   * @param marginType Initial or maintenance margin.
   * @return strikeValue Value of assets or debt of options of a given strike.
   */
  function _calcStrikeValue(StrikeHolding memory strikeHoldings, MarginType marginType)
    internal
    view
    returns (int strikeValue)
  {
    // todo [Josh]: get call, put, forward values
  }

  // Cash Margin Math

  /**
   * @notice Calculate the discounted value of cash in account.
   * @param marginType Initial or maintenance margin.
   * @return cashValue Discounted value of cash held in account.
   */
  function _calcCashValue(MarginType marginType) internal view returns (int cashValue) {
    // todo [Josh]: apply interest rate shock
  }

  //////////
  // Util //
  //////////

  /**
   * @notice Sort all option holdings into an array of
   *         [expiries][strikes][calls / puts / forwards].
   * @param assets Array of balances for given asset and subId.
   * @return expiryHoldings Sorted array of option holdings.
   */
  function _sortHoldings(AccountStructs.AssetBalance[] memory assets)
    internal
    view
    returns (ExpiryHolding[] memory expiryHoldings)
  {
    // 1. create sorted [expiries][strikes] 2D array
    for (uint i; i < assets.length; ++i) {
      if (address(assets[i].asset) == address(option)) {
        // decode subId
        (uint expiry, uint strike, bool isCall) = OptionEncoding.fromSubId(SafeCast.toUint96(assets[i].subId));

        // add new expiry or strike to holdings if unique
        (uint expiryIndex) = PCRMSorting.addUniqueExpiry(
          expiryHoldings, expiry, expiryHoldings.length
        );
        (uint strikeIndex) = PCRMSorting.addUniqueStrike(
          expiryHoldings, expiryIndex, strike, expiryHoldings[expiryIndex].strikes.length
        );

        // add call or put balance
        if (isCall) {
          expiryHoldings[expiryIndex].strikes[strikeIndex].calls += assets[i].balance;
        } else {
          expiryHoldings[expiryIndex].strikes[strikeIndex].puts += assets[i].balance;
        }
      }
    }

    // 2. pair off all symmetric calls and puts into forwards
    PCRMSorting.filterForwards(expiryHoldings);

    // todo [Josh]: add limit to # of expiries and # of options
  }

  //////////
  // View //
  //////////

  /**
   * @notice Sort all option holdings of an account into an array of
   *         [expiries][strikes][calls / puts / forwards].
   * @param accountId ID of account to sort.
   * @return expiryHoldings Sorted array of option holdings.
   */
  function getSortedHoldings(uint accountId) external view returns (ExpiryHolding[] memory expiryHoldings) {}

  /**
   * @notice Calculate the initial margin of account.
   *         A negative value means the account is X amount over the required margin.
   * @param expiries Sorted array of option holdings.
   * @return margin Amount by which account is over or under the required margin.
   */
  // todo [Josh]: public view function to get margin values directly through accountId
  function getInitialMargin(ExpiryHolding[] memory expiries) external view returns (int margin) {
    return _calcMargin(expiries, MarginType.INITIAL);
  }

  /**
   * @notice Calculate the maintenance margin of account.
   *         A negative value means the account is X amount over the required margin.
   * @param expiries Sorted array of option holdings.
   * @return margin Amount by which account is over or under the required margin.
   */
  function getMaintenanceMargin(ExpiryHolding[] memory expiries) external view returns (int margin) {
    return _calcMargin(expiries, MarginType.MAINTENANCE);
  }

  ////////////
  // Errors //
  ////////////

  error PCRM_OnlyAuction(address sender, address auction);
}
