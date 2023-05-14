// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface ILyraSpotFeed {
  struct SpotData {
    uint128 price;
    uint64 nonce;
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
  error LSF_InvalidNonce();

  ////////////////////////
  //       Events       //
  ////////////////////////
  event SpotPriceUpdated(uint128 spot, uint128 nonce);

  event SignerUpdated(address indexed signer, bool isWhitelisted);
}
