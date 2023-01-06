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

  uint32[20] jumps;
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
  }

  constructor(address _spotFeeds, uint _feedId, JumpParams memory _params, uint32[20] memory _initialJumps) {
    spotFeeds = ISpotFeeds(_spotFeeds);
    feedId = _feedId;
    params = _params;
    jumps = _initialJumps;
  }


}