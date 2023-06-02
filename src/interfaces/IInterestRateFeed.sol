// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface IInterestRateFeed {
  function getInterestRate(uint64 expiry) external view returns (int96 interestRate, uint64 confidence);
}
