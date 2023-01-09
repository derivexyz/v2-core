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

  ISpotFeeds public spotFeeds;
  uint public feedId;

  uint32[16] jumps;
  JumpParams public params;

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

  function recordJump() external {
    JumpParams memory memParams = params;
    uint32 currentTime = uint32(block.timestamp);
    uint liveSpot = spotFeeds.getSpot(feedId);

    if (memParams.referenceUpdatedAt + memParams.secToReferenceStale < currentTime) {
      // update reference price if stale
      memParams.referencePrice = liveSpot;
      memParams.referenceUpdatedAt = currentTime;
    } else {
      // calculate jump amount and store
      uint32 jump = _calcSpotJump(liveSpot, memParams.referencePrice);
      _maybeStoreJump(memParams.start, memParams.width, jump, currentTime);
    }

    // update jump params
    memParams.jumpUpdatedAt = currentTime;
    params = memParams;
  }

  function getMaxJump() external view returns (uint32 jump) {
    JumpParams memory memParams = params;
    uint32 currentTime = uint32(block.timestamp);
    if (currentTime - memParams.jumpUpdatedAt > memParams.secToJumpStale) {
      revert SJO_OracleIsStale(currentTime, memParams.jumpUpdatedAt, memParams.secToJumpStale);
    }

    uint32[16] memory memJumps = jumps;
    uint length = memJumps.length;
    uint32 i = uint32(length) - 1;
    while (i != 0 || jump != 0) {
      if (memJumps[i] > currentTime - memParams.duration) {
        jump = memParams.width * (i + 1);
      }
      i--;
    } 
  }

  function _calcSpotJump(uint liveSpot, uint referencePrice) internal pure returns (uint32 jump) {
    // get percent jump relative to reference
    uint jumpDecimal = IntLib.abs(
      (liveSpot.divideDecimal(referencePrice)).toInt256() - DecimalMath.UNIT.toInt256()
    );
    // convert to uint32 basis points
    jump = (jumpDecimal.multiplyDecimal(100) / DecimalMath.UNIT).toUint32();
  }

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

  error SJO_OracleIsStale(uint32 currentTime, uint32 lastUpdatedAt, uint32 staleLimit);

  error SJO_MaxJumpExceedsLimit();

}