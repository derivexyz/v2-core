// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface IMTMCache {
  struct Expiry {
    uint64 secToExpiry;
    uint128 forwardPrice;
    uint64 discountFactor;
  }

  struct Option {
    uint128 strike;
    uint128 vol;
    int amount;
    bool isCall;
  }

  function getExpiryMTM(Expiry memory expiryDetails, Option[] memory options) external view returns (int);
}
