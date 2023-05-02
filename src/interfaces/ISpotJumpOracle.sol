// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "openzeppelin/utils/math/SafeCast.sol";
import "lyra-utils/decimals/DecimalMath.sol";
import "lyra-utils/math/IntLib.sol";

import "forge-std/console2.sol";

/**
 * @title ISpotJumpOracle
 * @author Lyra
 * @notice Stores and finds max jump in the spot price during the last X days using a rolling "referencePrice"
 */

interface ISpotJumpOracle {
  struct JumpParams {
    // 500 bps would imply the first bucket is 5% -> 5% + width
    uint32 start;
    // 150 bps would imply [0-1.5%, 1.5-3.0%, ...]
    uint32 width;
    // update timestamp of the spotFeed price used as reference
    uint32 referenceUpdatedAt;
    // sec until reference price is considered stale
    uint32 secToReferenceStale;
    // reference price used when calculating jump bp
    uint128 referencePrice;
  }

  ////////////
  // Events //
  ////////////

  event JumpUpdated(uint32 jump, uint livePrice, uint referencePrice);

  //////////////////////
  // Public Variables //
  //////////////////////

  /// @dev stores update timestamp of the spotFeed price for which jump was calculated
  function jumps(uint index) external returns (uint32 jump);

  /// @dev stores all parameters required to store the jump
  function params()
    external
    returns (uint32 start, uint32 width, uint32 referenceUpdatedAt, uint32 secToReferenceStale, uint128 referencePrice);

  //////////////
  // External //
  //////////////

  /**
   * @notice Updates the jump buckets if livePrice deviates far enough from the referencePrice.
   * @dev The time gap between the livePrice and referencePrice fluctuates,
   *      but is always < params.secToReferenceStale.
   */
  function updateJumps() external;

  /**
   * @notice Returns the max jump (rounded down) that is not stale.
   *         If there is no jump that is > params.start, 0 is returned.
   * @param secToJumpStale sec that jump is considered as valid
   * @return jump The largest jump amount denominated in basis points.
   */
  function getMaxJump(uint32 secToJumpStale) external view returns (uint32 jump);

  ////////////
  // Errors //
  ////////////

  error SJO_MaxJumpExceedsLimit();
}
