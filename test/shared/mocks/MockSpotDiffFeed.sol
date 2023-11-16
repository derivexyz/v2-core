// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import {ISpotDiffFeed} from "../../../src/interfaces/ISpotDiffFeed.sol";
import {ISpotFeed} from "../../../src/interfaces/ISpotFeed.sol";

import "forge-std/console2.sol";

contract MockSpotDiffFeed is ISpotDiffFeed {
  ISpotFeed public spotFeed;
  int public spotDiff;
  uint public confidence;

  constructor(ISpotFeed _spotFeed) {
    spotFeed = _spotFeed;
    confidence = 1e18;
  }

  function setSpotFeed(ISpotFeed _spotFeed) external {
    spotFeed = _spotFeed;
  }

  function setSpotDiff(int _spotDiff, uint _confidence) external {
    spotDiff = _spotDiff;
    confidence = _confidence;
  }

  function getResult() external view returns (uint, uint) {
    (uint spot,) = spotFeed.getSpot();
    return (uint(int(spot) + spotDiff), confidence);
  }
}
