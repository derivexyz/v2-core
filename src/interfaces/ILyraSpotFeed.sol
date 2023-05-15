// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface ILyraSpotFeed {
  struct SpotData {
    // price data
    uint96 price;
    uint96 confidence;
    uint64 timestamp;
    // the lastest timestamp you can use this data
    uint deadline;
    // signature v, r, s
    address signer;
    bytes signature;
  }

  /// @dev bad signature
  error LSF_InvalidSignature();

  /// @dev Invalid signer
  error LSF_InvalidSigner();

  /// @dev submission is expired
  error LSF_DataExpired();

  /// @dev invalid nonce
  error LSF_InvalidTimestamp();

  ////////////////////////
  //       Events       //
  ////////////////////////
  event SpotPriceUpdated(address indexed signer, uint96 spot, uint96 confidence, uint64 timestamp);

  event SignerUpdated(address indexed signer, bool isWhitelisted);
}
