// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./IAsset.sol";
import "./IInterestRateModel.sol";
import "./ISettlementFeed.sol";

interface IOption is IAsset {
  /////////////////
  //   Structs   //
  /////////////////

  struct OISnapshot {
    bool initialized;
    uint240 oi;
  }

  ///////////////////
  //   Functions   //
  ///////////////////

  /**
   * @notice Get settlement value of a specific option.
   * @dev Will return false if option not settled yet.
   * @param subId ID of option.
   * @param balance Amount of option held.
   * @return payout Amount the holder will receive or pay when position is settled
   * @return priceSettled Whether the settlement price of the option has been set.
   */
  function calcSettlementValue(uint subId, int balance) external view returns (int payout, bool priceSettled);

  function openInterestBeforeTrade(uint subId, uint tradeId) external view returns (bool initialized, uint240 oi);

  function openInterest(uint subId) external view returns (uint oi);

  function getSettlementValue(uint strikePrice, int balance, uint settlementPrice, bool isCall)
    external
    pure
    returns (int);

  ////////////////
  //   Events   //
  ////////////////

  /// @dev Emitted when interest related state variables are updated
  event SnapshotTaken(uint subId, uint tradeId, uint oi);

  ////////////////
  //   Errors   //
  ////////////////

  /// @dev revert if caller is not Accounts
  error OA_NotAccounts();

  /// @dev revert when settlement is triggered from unknown managers
  error OA_UnknownManager();
}
