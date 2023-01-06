// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;


/**
 * @title SpotJumpOracle
 * @author Lyra
 * @notice Can be used to find spot jumps in the last X days as a proxy for Realized Volatility
 */

contract SpotJumpOracle {
  ISpotFeeds public spotFeeds;
  uint public feedId;
  constructor(address _spotFeeds, uint _feedId) {
    spotFeeds = ISpotFeeds(_spotFeeds);
    feedId = _feedId;
  }

  
}