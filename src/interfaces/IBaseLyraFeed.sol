// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface IBaseLyraFeed {
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

  ////////////////////////
  //       Events       //
  ////////////////////////

  event SignerUpdated(address indexed signer, bool isWhitelisted);
  event HeartbeatUpdated(address indexed signer, uint heartbeat);
}
