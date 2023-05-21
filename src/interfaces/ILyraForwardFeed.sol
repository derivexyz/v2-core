// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface ILyraForwardFeed {
  struct ForwardData {
    uint64 expiry;
    uint96 forwardPrice;
    uint settlementStartAggregate;
    uint currentSpotAggregate;
    uint64 confidence;
    uint64 timestamp;
    // the latest timestamp you can use this data
    uint deadline;
    // signature v, r, s
    address signer;
    bytes signature;
  }

  /// @dev structure to store in contract storage
  struct ForwardDetails {
    uint96 forwardPrice;
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
