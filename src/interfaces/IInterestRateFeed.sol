// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IInterestRateFeed {
  function getInterestRate(uint64 expiry) external view returns (int interestRate, uint confidence);
}
