// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/interfaces/ISpotFeeds.sol";

/**
 * @title SpotJumpOracle
 * @author Lyra
 * @notice Can be used to find spot jumps in the last X days as a proxy for Realized Volatility
 */

contract SpotJumpOracle {
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
    uint32 staleLimit;
    // sec to reference spot used to calculate jump
    uint32 secToReference;
    // last timestamp of update
    uint32 lastUpdatedAt;
  }

  constructor(address _spotFeeds, uint _feedId, JumpParams memory _params, uint32[16] memory _initialJumps) {
    spotFeeds = ISpotFeeds(_spotFeeds);
    feedId = _feedId;
    params = _params;
    jumps = _initialJumps;

    if (uint(_initialJumps.length) * uint(_params.width) > type(uint32).max) {
      revert SJO_MaxJumpExceedsLimit();
    }
  }

  function recordJump(uint referenceRoundId) external {
    JumpParams memory memParams = params;
    uint32 currentTime = uint32(block.timestamp);
    
    // todo [Josh]: how is referenceSpot taken?
    // - querying from Chainlink using roundId?
    // - or using previous liveSpots
    // - may need to use .getSpotAndUpdatedAt to get exact time of update
  }

  function getMaxJump() external view returns (uint32 jump) {
    JumpParams memory memParams = params;
    uint32 currentTime = uint32(block.timestamp);
    if (currentTime - memParams.lastUpdatedAt > memParams.staleLimit) {
      revert SJO_OracleIsStale(currentTime, memParams.lastUpdatedAt, memParams.staleLimit);
    }

    uint32[16] memory memJumps = jumps;
    uint length = memJumps.length;
    uint32 i = uint32(length) - 1;
    uint32 jump;
    while (i != 0 || jump != 0) {
      if (memJumps[i] > currentTime - memParams.duration) {
        jump = memParams.width * (i + 1);
      }
      i--;
    } 
  }

  function _getSpotJump() internal view {
    uint spotPrice = spotFeeds.getSpot(feedId);
  }

  error SJO_OracleIsStale(uint32 currentTime, uint32 lastUpdatedAt, uint32 staleLimit);

  error SJO_MaxJumpExceedsLimit();

}