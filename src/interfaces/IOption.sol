// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IAsset} from "src/interfaces/IAsset.sol";
import {IManager} from "src/interfaces/IManager.sol";

import {IPositionTracking} from "src/interfaces/IPositionTracking.sol";
import {IGlobalSubIdOITracking} from "./IGlobalSubIdOITracking.sol";

interface IOption is IAsset, IPositionTracking, IGlobalSubIdOITracking {
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

  function getSettlementValue(uint strikePrice, int balance, uint settlementPrice, bool isCall)
    external
    pure
    returns (int);

  ////////////////
  //   Errors   //
  ////////////////

  /// @dev revert if caller is not Accounts
  error OA_NotAccounts();

  /// @dev revert when settlement is triggered from unknown managers
  error OA_UnknownManager();
}
