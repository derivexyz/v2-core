// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface IOptionPricing {
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

  function getExpiryOptionsValue(Expiry memory expiryDetails, Option[] memory options) external view returns (int);
  function getOptionValue(Expiry memory expiryDetails, Option memory option) external view returns (int);
}
