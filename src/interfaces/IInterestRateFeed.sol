// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

interface IInterestRateFeed {
  function getInterestRate(uint64 expiry) external view returns (int interestRate, uint confidence);
}
