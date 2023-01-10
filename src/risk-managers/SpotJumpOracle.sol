// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/interfaces/ISpotFeeds.sol";
import "src/libraries/IntLib.sol";
import "synthetix/DecimalMath.sol";
import "openzeppelin/utils/math/SafeCast.sol";

/**
 * @title SpotJumpOracle
 * @author Lyra
 * @notice Can be used to find spot jumps in the last X days as a proxy for Realized Volatility
 */

contract SpotJumpOracle {
  using SafeCast for uint;
  using DecimalMath for uint;
  using IntLib for int;

  struct JumpParams {
    // 500 bps would imply the first bucket is 5% -> 5% + width 
    uint32 start;
    // 150 bps would imply [0-1.5%, 1.5-3.0%, ...]
    uint32 width;
    // sec until jump is discarded
    uint32 duration;
    // sec until value is considered stale
    uint32 secToJumpStale;
    // last timestamp of update
    uint32 jumpUpdatedAt;
    // last timestamp of reference price update
    uint32 referenceUpdatedAt;
    // sec until reference price is considered stale
    uint32 secToReferenceStale;
    // price at last update
    uint256 referencePrice;
  }

  ///////////////
  // Variables //
  ///////////////

  /// @dev address of ISpotFeed for price
  ISpotFeeds public spotFeeds;
  /// @dev id of feed used when querying price from spotFeeds
  uint public feedId;
  
  /// @dev each slot stores timestamp at which jump was stored
  uint32[16] public jumps;
  /// @dev stores all parameters required to store the jump
  JumpParams public params;

  ////////////
  // Events //
  ////////////

  event JumpUpdated(uint32 jump, uint livePrice, uint referencePrice);

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(address _spotFeeds, uint _feedId, JumpParams memory _params, uint32[16] memory _initialJumps) {
    spotFeeds = ISpotFeeds(_spotFeeds);
    feedId = _feedId;
    params = _params;
    jumps = _initialJumps;

    // ensure multiplication in recordJump() does not overflow
    if (uint(_initialJumps.length) * uint(_params.width) > type(uint32).max) {
      revert SJO_MaxJumpExceedsLimit();
    }
  }

  //////////////
  // External //
  //////////////

  /**
   * @notice Updates the jump buckets if livePrice deviates far enough from the referencePrice.
   * @dev The time gap between the livePrice and referencePrice is always < params.secToReferenceStale.
          However, this means the time gap is not always.
   */
  function updateJumps() external {
    JumpParams memory memParams = params;
    uint32 currentTime = uint32(block.timestamp);
    uint livePrice = spotFeeds.getSpot(feedId);

    uint32 jump;
    if (memParams.referenceUpdatedAt + memParams.secToReferenceStale < currentTime) {
      // update reference price if stale
      memParams.referencePrice = livePrice;
      memParams.referenceUpdatedAt = currentTime;
    } else {
      // calculate jump amount and store
      jump = _calcSpotJump(livePrice, memParams.referencePrice);
      _maybeStoreJump(memParams.start, memParams.width, jump, currentTime);
    }

    // update jump params
    memParams.jumpUpdatedAt = currentTime;
    params = memParams;

    emit JumpUpdated(jump, livePrice, memParams.referencePrice);
  }

  /**
   * @notice Returns the max jump that is not stale.
   *         If there is no jump that is > params.start, 0 is returned.
   * @return jump The largest jump amount denominated in basis points.
   */
  function getMaxJump() external view returns (uint32 jump) {
    JumpParams memory memParams = params;
    uint32 currentTime = uint32(block.timestamp);

    // revert if oracle has not been updated within 'secToJumpStale'
    if (currentTime - memParams.jumpUpdatedAt > memParams.secToJumpStale) {
      revert SJO_OracleIsStale(currentTime, memParams.jumpUpdatedAt, memParams.secToJumpStale);
    }

    // traverse jumps in descending order, finding the first non-stale jump
    uint32[16] memory memJumps = jumps;
    uint length = memJumps.length;
    uint32 i = uint32(length) - 1;
    while (i > 0 && jump == 0) {
      if (memJumps[i] + memParams.duration > currentTime) {
        // if jump value not stale, return
        jump = memParams.start + memParams.width * (i + 1);
      }
      i--;
    }
  }


  /////////////
  // Helpers //
  /////////////

  /**
   * @notice Finds the percentage difference between two prices and converts to basis points.
   * @dev Values are always rounded down.
   * @param liveSpot Current price taken from spotFeeds
   * @param referencePrice Price recoreded in previous updates but < params.secToReferenceStale
   * @return jump Difference between two prices in basis points
   */

  function _calcSpotJump(uint liveSpot, uint referencePrice) internal pure returns (uint32 jump) {
    // get percent jump relative to reference
    uint jumpDecimal = IntLib.abs(
      (liveSpot.divideDecimal(referencePrice)).toInt256() - DecimalMath.UNIT.toInt256()
    );
    // convert to uint32 basis points
    jump = (jumpDecimal.multiplyDecimal(100) / DecimalMath.UNIT).toUint32();
  }

  /**
   * @notice Stores the timestamp at which jump was recorded if jump > params.start.
   * @param start Jump amount of the first bucket in basis points
   * @param width Size of bucket in basis points
   * @param jump Current price jump in basis points
   * @param timestamp Timestamp at which jump was calculated
   */
  function _maybeStoreJump(
    uint32 start, 
    uint32 width, 
    uint32 jump,
    uint32 timestamp
  ) internal {
    uint numBuckets = jumps.length;

    // if jump is greater than the last bucket, store in the last bucket
    if (jump > start + (width * jumps.length)) {
      jumps[numBuckets - 1] = timestamp;
    }

    // otherwise, find bucket for jump
    if (jump > start) {
      jumps[(jump - start) / width] = timestamp;
    }
  }

  ////////////
  // Errors //
  ////////////

  error SJO_OracleIsStale(uint32 currentTime, uint32 lastUpdatedAt, uint32 staleLimit);

  error SJO_MaxJumpExceedsLimit();

}