// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/utils/math/SignedMath.sol";
import "openzeppelin/utils/math/SafeCast.sol";

import "src/interfaces/IOption.sol";
import "src/interfaces/ISpotFeeds.sol";
import "src/interfaces/IAccounts.sol";
import "src/interfaces/ISettlementFeed.sol";

import "src/libraries/Owned.sol";
import "src/libraries/OptionEncoding.sol";
import "src/libraries/SignedDecimalMath.sol";
import "src/libraries/IntLib.sol";

/**
 * @title Option
 * @author Lyra
 * @notice Option asset that defines subIds, value and settlement
 */
contract Option is IOption, Owned {
  using SafeCast for uint;
  using SafeCast for int;
  using SignedDecimalMath for int;

  /// @dev Address of the Account module
  IAccounts immutable accounts;

  /// @dev Contract to get spot prices which are locked in at settlement
  ISpotFeeds public spotFeed;

  ///////////////
  // Variables //
  ///////////////

  ///@dev Id used to query spot price
  uint public feedId;

  ///@dev SubId => tradeId => open interest snapshot
  mapping(uint => mapping(uint => OISnapshot)) public openInterestBeforeTrade;

  ///@dev OI for a subId. OI is the sum of all positive balance
  mapping(uint => uint) public openInterest;

  ///@dev Expiry => Settlement price
  mapping(uint => uint) public settlementPrices;

  ///@dev Whitelisted managers. Only accounts controlled by whitelisted managers can trade this asset.
  mapping(address => bool) public whitelistedManager;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(IAccounts _accounts, address _spotFeeds, uint _feedId) {
    accounts = _accounts;
    spotFeed = ISpotFeeds(_spotFeeds);
    feedId = _feedId;
  }

  //////////////////////////////
  //   Owner-only Functions   //
  //////////////////////////////

  /**
   * @notice Whitelist or un-whitelist a manager
   * @param _manager manager address
   * @param _whitelisted true to whitelist
   */
  function setWhitelistManager(address _manager, bool _whitelisted) external onlyOwner {
    whitelistedManager[_manager] = _whitelisted;

    emit WhitelistManagerSet(_manager, _whitelisted);
  }

  ///////////////
  // Transfers //
  ///////////////

  function handleAdjustment(
    AccountStructs.AssetAdjustment memory adjustment,
    uint tradeId,
    int preBalance,
    IManager manager,
    address /*caller*/
  ) external onlyAccount returns (int finalBalance, bool needAllowance) {
    _checkManager(address(manager));

    // todo: make sure valid subId

    // take snapshot of OI if this subId has not been traded in this tradeId
    if (!openInterestBeforeTrade[adjustment.subId][tradeId].initialized) {
      openInterestBeforeTrade[adjustment.subId][tradeId].initialized = true;
      openInterestBeforeTrade[adjustment.subId][tradeId].oi = openInterest[adjustment.subId].toUint240();
    }

    // update the OI based on pre balance and change amount
    _updateOI(adjustment.subId, preBalance, adjustment.amount);

    return (preBalance + adjustment.amount, adjustment.amount < 0);
  }

  /**
   * @notice Triggered when a user wants to migrate an account to a new manager
   * @dev block update with non-whitelisted manager
   */
  function handleManagerChange(uint, /*accountId*/ IManager newManager) external view onlyAccount {
    _checkManager(address(newManager));
  }

  ////////////////
  // Settlement //
  ////////////////

  /**
   * @notice Locks-in price which the option settles at for an expiry.
   * @dev Settlement handled by option to simplify multiple managers settling same option
   * @param expiry Timestamp of when the option expires
   */
  function setSettlementPrice(uint expiry) external {
    if (settlementPrices[expiry] != 0) revert SettlementPriceAlreadySet(expiry, settlementPrices[expiry]);
    if (expiry > block.timestamp) revert NotExpired(expiry, block.timestamp);

    settlementPrices[expiry] = spotFeed.getSpot(feedId);
    emit SettlementPriceSet(expiry, 0);
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
   * @notice Get settlement value of a specific option.
   * @dev Will return false if option not settled yet.
   * @param subId ID of option.
   * @param balance Amount of option held.
   * @return payout Amount the holder will receive or pay when position is settled
   * @return priceSettled Whether the settlement price of the option has been set.
   */
  function calcSettlementValue(uint subId, int balance) external view returns (int payout, bool priceSettled) {
    (uint expiry, uint strike, bool isCall) = OptionEncoding.fromSubId(SafeCast.toUint96(subId));
    uint settlementPrice = settlementPrices[expiry];

    // Return false if settlement price has not been locked in
    if (settlementPrice == 0) {
      return (0, false);
    }

    return (getSettlementValue(strike, balance, settlementPrice, isCall), true);
  }

  //////////////
  // Internal //
  //////////////

  /**
   * @dev Revert if manager address is not whitelisted by this contract
   * @param manager manager address
   */
  function _checkManager(address manager) internal view {
    if (!whitelistedManager[manager]) revert OA_UnknownManager();
  }

  /**
   * @dev update global OI for an subId, base on adjustment of a single account
   * @param preBalance Account balance before an adjustment
   * @param change Change of balance
   */
  function _updateOI(uint subId, int preBalance, int change) internal {
    int postBalance = preBalance + change;
    openInterest[subId] =
      (openInterest[subId].toInt256() + SignedMath.max(0, postBalance) - SignedMath.max(0, preBalance)).toUint256();
  }

  function getSettlementValue(uint strikePrice, int balance, uint settlementPrice, bool isCall)
    public
    pure
    returns (int)
  {
    int priceDiff = settlementPrice.toInt256() - strikePrice.toInt256();

    if (isCall && priceDiff > 0) {
      // ITM Call
      return priceDiff.multiplyDecimal(balance);
    } else if (!isCall && priceDiff < 0) {
      // ITM Put
      return -priceDiff.multiplyDecimal(balance);
    } else {
      // OTM
      return 0;
    }
  }

  /////////////////
  //  Modifiers  //
  /////////////////

  modifier onlyAccount() {
    if (msg.sender != address(accounts)) revert OA_NotAccounts();
    _;
  }
}
