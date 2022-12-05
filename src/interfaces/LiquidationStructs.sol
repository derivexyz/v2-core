// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

enum AuctionState {
  NOT_EXIST,
  STARTED,
  ENDED
}

struct AuctionDetail {
  AuctionState status;
  address owner;
  uint accountId;
  uint initDebtValue;
  uint ratePerSecond; // the rate to increase the value of debt per second.
  uint percentageLeft; // percentage of position left
  uint64 startTimestamp;
}
