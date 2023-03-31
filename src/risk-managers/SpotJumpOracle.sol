// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/utils/math/SafeCast.sol";

import "../interfaces/IChainlinkSpotFeed.sol";
import "../interfaces/ISpotJumpOracle.sol";

import "../libraries/IntLib.sol";
import "../libraries/DecimalMath.sol";

import "forge-std/console2.sol";

/**
 * @title SpotJumpOracle
 * @author Lyra
 * @notice Stores and finds max jump in the spot price during the last X days using a rolling "referencePrice"
 * @dev The "jumps" value stores timestamps of all recorded jumps:
 *      bucket bounds:       [     100-125bp    ][     125-150bp    ][     150-175bp    ]...[    300bp-inf    ]
 *      actual value stored: [ 04:12:35, Jan 10 ][ 10:01:43, Dec 11 ][ 12:00:15, May 21 ]...[ 6:03:01, Feb 05 ]
 *
 *      When finding the "max jump", traverses the buckets in reverse order until the first non-stale jump is found
 */

contract SpotJumpOracle is ISpotJumpOracle {
  using SafeCast for uint;
  using DecimalMath for uint;
  using IntLib for int;

  ///////////////
  // Variables //
  ///////////////

  /// @dev address of IChainlinkSpotFeed for price
  IChainlinkSpotFeed public spotFeed;
  /// @dev number of distinct jump buckets
  uint internal constant NUM_BUCKETS = 16;
  /// @dev stores update timestamp of the spotFeed price for which jump was calculated
  uint32[NUM_BUCKETS] public jumps;
  /// @dev stores all parameters required to store the jump
  ISpotJumpOracle.JumpParams public params;

  /// @dev maximum value of a uint32 used to prevent overflows
  uint public constant UINT32_MAX = 0xFFFFFFFF;

  /// @dev conversion constant from percent decimal to bp.
  uint public constant BASIS_POINT_DECIMALS = 10000;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(IChainlinkSpotFeed _spotFeed, JumpParams memory _params, uint32[NUM_BUCKETS] memory _initialJumps) {
    spotFeed = _spotFeed;
    params = _params;
    jumps = _initialJumps;

    // ensure multiplication in _maybeStoreJump() does not overflow
    if (uint(NUM_BUCKETS) * uint(_params.width) > UINT32_MAX) {
      revert SJO_MaxJumpExceedsLimit();
    }
  }

  //////////////
  // External //
  //////////////

  /**
   * @notice Updates the jump buckets if livePrice deviates far enough from the referencePrice.
   * @dev The time gap between the livePrice and referencePrice fluctuates,
   *      but is always < params.secToReferenceStale.
   */
  function updateJumps() public {
    JumpParams memory memParams = params;
    (uint livePrice, uint updatedAt) = spotFeed.getSpotAndUpdatedAt();
    uint32 spotUpdatedAt = uint32(updatedAt);

    // calculate jump basis points and store
    // stale reference price is used for safety
    uint32 jump = _calcSpotJump(livePrice, uint(memParams.referencePrice));
    _maybeStoreJump(memParams.start, memParams.width, jump, spotUpdatedAt);

    // update reference price if stale
    if (memParams.referenceUpdatedAt + memParams.secToReferenceStale < spotUpdatedAt) {
      memParams.referencePrice = livePrice.toUint128();
      memParams.referenceUpdatedAt = spotUpdatedAt;
    }

    // update jump params
    params = memParams;

    emit JumpUpdated(jump, livePrice, memParams.referencePrice);
  }

  /**
   * @notice Returns the max jump (rounded down) that is not stale..
   *         If there is no jump that is > params.start, 0 is returned.
   * @param secToJumpStale sec that jump is considered as valid
   * @return jump The largest jump amount denominated in basis points.
   */
  function getMaxJump(uint32 secToJumpStale) external view returns (uint32 jump) {
    JumpParams memory memParams = params;
    uint32 currentTime = uint32(block.timestamp);

    // traverse jumps in descending order, finding the first non-stale jump
    uint32[NUM_BUCKETS] memory memJumps = jumps;
    for (uint32 i = uint32(NUM_BUCKETS); i > 0; i--) {
      if (memJumps[i - 1] + secToJumpStale > currentTime) {
        // return largest jump that's not stale
        return memParams.start + memParams.width * (i - 1);
      }
    }
  }

  /////////////
  // Helpers //
  /////////////

  /**
   * @notice Finds the percentage difference between two prices and converts to basis points.
   * @dev Values are always rounded down.
   * @param liveSpot Current price taken from spotFeed
   * @param referencePrice Price recoreded in previous updates but < params.secToReferenceStale
   * @return jump Difference between two prices in basis points
   */

  function _calcSpotJump(uint liveSpot, uint referencePrice) internal pure returns (uint32 jump) {
    // get ratio
    uint ratio =
      liveSpot > referencePrice ? liveSpot.divideDecimal(referencePrice) : referencePrice.divideDecimal(liveSpot);

    // get percent
    uint jumpDecimal = IntLib.abs(ratio.toInt256() - DecimalMath.UNIT.toInt256());

    // convert to basis points with 0 decimals
    uint jumpBasisPoints = jumpDecimal * BASIS_POINT_DECIMALS / DecimalMath.UNIT;

    // gracefully handle huge spot jump
    return (jumpBasisPoints < UINT32_MAX) ? (jumpBasisPoints).toUint32() : uint32(UINT32_MAX);
  }

  /**
   * @notice Stores the timestamp at which jump was recorded if jump > params.start.
   * @param start Jump amount of the first bucket in basis points
   * @param width Size of bucket in basis points
   * @param jump Current price jump in basis points
   * @param timestamp Timestamp at which jump was calculated
   */
  function _maybeStoreJump(uint32 start, uint32 width, uint32 jump, uint32 timestamp) internal {
    // return zero if below threshold
    if (jump < start) return;

    uint idx = (jump - start) / width;

    // if jump is greater than the last bucket, store in the last bucket
    if (idx >= NUM_BUCKETS) {
      idx = NUM_BUCKETS - 1;
    }
    jumps[idx] = timestamp;
  }
}
