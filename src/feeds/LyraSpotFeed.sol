// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "src/interfaces/ISpotFeed.sol";
import "src/interfaces/IUpdatableOracle.sol";

/**
 * @title LyraSpotFeed
 * @author Lyra
 * @notice Spot feed that takes off-chain updates, verify signature and update on-chain
 */
contract LyraSpotFeed is ISpotFeed, IUpdatableOracle {
  // todo: potentially be updatable
  uint64 public immutable staleLimit;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor() {}

  /**
   * @notice Gets spot price
   * @return spotPrice Spot price with 18 decimals.
   */
  function getSpot() public view returns (uint spotPrice) {
    

  }

  function updatePrice(bytes calldata data) external {
    // parse data, verify signature

    // update spot
  }
}
