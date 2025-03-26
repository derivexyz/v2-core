// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

// inherited
import "openzeppelin/access/Ownable2Step.sol";

// interfaces
import {ISpotDiffFeed, ISpotFeed} from "../../interfaces/ISpotDiffFeed.sol";

/**
 * @title LyraStaticSpotDiffFeed
 * @author Lyra
 * @notice Fixed spot diff feed for when a market is deprecated
 */
contract LyraStaticSpotDiffFeed is Ownable2Step, ISpotDiffFeed {
  uint public finalValue;
  uint public confidence;

  // Required for ISpotDiffFeed
  ISpotFeed public spotFeed;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor() Ownable(msg.sender) {}

  ////////////////////////
  //  Public Functions  //
  ////////////////////////

  function setFixedResult(uint _finalValue, uint _confidence) external onlyOwner {
    finalValue = _finalValue;
    confidence = _confidence;

    emit SpotDiffValueUpdated(_finalValue, _confidence);
  }

  /**
   * @notice Gets final spot diff value
   * @return spotPrice Spot price with 18 decimals.
   */
  function getResult() public view returns (uint, uint) {
    return (finalValue, confidence);
  }

  event SpotDiffValueUpdated(uint finalValue, uint confidence);
}
