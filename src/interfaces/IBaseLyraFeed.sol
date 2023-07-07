// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface IBaseLyraFeed {
  function domainSeparator() external view returns (bytes32);

  function FEED_DATA_TYPEHASH() external view returns (bytes32);

  struct FeedData {
    // custom data field
    bytes data;
    // the latest timestamp you can use this data
    uint deadline;
    // timestamp that this data is signed
    uint64 timestamp;
    // signer of this data
    address[] signers;
    // signature v, r, s
    bytes[] signatures;
  }

  ////////////////////////
  //       Errors       //
  ////////////////////////

  /// @dev bad signature
  error BLF_InvalidSignature();

  /// @dev Invalid signer
  error BLF_InvalidSigner();

  /// @dev submission is expired
  error BLF_DataExpired();

  /// @dev invalid nonce
  error BLF_InvalidTimestamp();

  /// @dev Data has crossed heartbeat threshold
  error BLF_DataTooOld();

  /// @dev Invalid required signers
  error BLF_InvalidRequiredSigners();

  /// @dev Not enough signers
  error BLF_NotEnoughSigners();

  /// @dev Duplicated signer used in array of signers
  error BLF_DuplicatedSigner();

  /// @dev Submitted signatures and signers length mismatch
  error BLF_SignatureSignersLengthMismatch();

  ////////////////////////
  //       Events       //
  ////////////////////////

  event SignerUpdated(address indexed signer, bool isWhitelisted);
  event HeartbeatUpdated(address indexed signer, uint heartbeat);
  event RequiredSignersUpdated(uint requiredSigners);
}
