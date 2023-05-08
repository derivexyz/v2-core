// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface IDiscountFactorFeed {
  function getDiscountFactor(uint expiry) external view returns (uint64 discountFactor, uint64 confidence);

  ////////////
  // Events //
  ////////////

  /// @dev Emitted when spot price for option settlement determined
  event DiscountFactorSet(uint64 discountFactor, uint64 confidence);
}
