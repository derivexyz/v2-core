// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

enum AuctionState {
  NOT_EXIST,
  STARTED,
  ENDED
}

// todo: if we let the liquidation module hold the account, has to keep track of the original owner
struct AuctionDetail {
  AuctionState status;
  uint accountId;
  uint initDebtValue;
  uint ratePerSecond; // the rate to increase the value of debt per second.
  uint percentageLeft; // percentage of position left
  uint64 startTimestamp;
}
