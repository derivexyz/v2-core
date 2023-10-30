// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IVolFeed {
  function getVol(uint128 strike, uint64 expiry) external view returns (uint vol, uint confidence);

  function getExpiryMinConfidence(uint64 expiry) external view returns (uint confidence);

  ////////////
  // Events //
  ////////////

  /// @dev Emitted when spot price for option settlement determined
  event VolSet(uint128 strike, uint128 expiry, uint128 vol, uint64 confidence);
}
