// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {ISpotFeed} from "./ISpotFeed.sol";

interface ILyraForwardFeed {
  /// @dev structure to store in contract storage
  struct ForwardDetails {
    int96 fwdSpotDifference;
    uint64 confidence;
    uint64 timestamp;
  }

  struct SettlementDetails {
    uint settlementStartAggregate;
    uint currentSpotAggregate;
  }

  ////////////////////////
  //       Events       //
  ////////////////////////
  event SpotFeedUpdated(ISpotFeed spotFeed);
  event SettlementHeartbeatUpdated(uint64 settlementHeartbeat);
  event ForwardDataUpdated(
    uint64 indexed expiry, address indexed signer, ForwardDetails fwdDetails, SettlementDetails settlementDetails
  );

  ////////////////////////
  //       Errors       //
  ////////////////////////
  error LFF_MissingExpiryData();
  error LFF_InvalidConfidence();
  error LFF_InvalidSettlementData();
  error LFF_InvalidFwdDataTimestamp();
  error LFF_InvalidDataTimestampForSettlement();
  error LFF_SettlementDataTooOld();
}
