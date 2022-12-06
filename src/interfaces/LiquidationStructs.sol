// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

enum AuctionState {
  NOT_EXIST,
  STARTED,
  ENDED
}

/**
 * auction detail
 * @todo: pack storage to save gas?
 */
struct AuctionDetail {
  /// @dev status of the auction
  AuctionState status;
  
  /// @dev origin owner of the account
  address owner;
  
  /// @dev accountId
  uint accountId;
  
  /// @dev positive number indicating initial amount of total debt
  ///      represent "How much cash to pay liquidator" to take the whole position
  ///      it should be be initialised as the total intrisic value of all short positions.
  uint initDebtValue;
  
  /// @dev the rate to increase the value of debt per second
  ///      the debt should be increasing overtime (willing to pay more for someone to take this position) 
  ///      and be capped at total cash in the account.
  uint ratePerSecond; 
  
  /// @dev percentage of position left to be auctioned.
  uint percentageLeft;
  
  /// @dev timestamp that the auction started at
  uint64 startTimestamp;
}
