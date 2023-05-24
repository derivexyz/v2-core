// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface IVolFeed {
  function getVol(uint128 strike, uint64 expiry) external view returns (uint128 vol, uint64 confidence);

  function getExpiryMinConfidence(uint64 expiry) external view returns (uint64 confidence);

  ////////////
  // Events //
  ////////////

  /// @dev Emitted when spot price for option settlement determined
  event VolSet(uint128 strike, uint128 expiry, uint128 vol, uint64 confidence);
}
