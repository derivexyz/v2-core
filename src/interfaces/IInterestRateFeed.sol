// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface IInterestRateFeed {
  function getInterestRate(uint expiry) external view returns (uint64 interestRate, uint64 confidence);

  ////////////
  // Events //
  ////////////

  /// @dev Emitted when spot price for option settlement determined
  event InterestRateSet(uint64 interestRate, uint64 confidence);
}
