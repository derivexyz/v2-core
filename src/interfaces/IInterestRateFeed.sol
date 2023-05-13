// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface IInterestRateFeed {
  function getInterestRate(uint expiry) external view returns (int64 interestRate, uint64 confidence);

  ////////////
  // Events //
  ////////////

  /// @dev Emitted when spot price for option settlement determined
  event InterestRateSet(int64 interestRate, uint64 confidence);
}
