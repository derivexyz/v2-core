// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

// inherited
import "openzeppelin/access/Ownable2Step.sol";

// interfaces
import {ISpotFeed} from "../../interfaces/ISpotFeed.sol";

/**
 * @title LyraStaticSpotFeed
 * @author Lyra
 * @notice Fixed spot feed for when a market is deprecated
 */
contract LyraStaticSpotFeed is Ownable2Step, ISpotFeed {
  uint public price;
  uint public confidence;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor() Ownable(msg.sender) {}

  ////////////////////////
  //  Public Functions  //
  ////////////////////////

  function setSpot(uint _price, uint _confidence) external onlyOwner {
    price = _price;
    confidence = _confidence;

    emit SpotUpdated(_price, _confidence);
  }

  /**
   * @notice Gets spot price
   * @return spotPrice Spot price with 18 decimals.
   */
  function getSpot() public view returns (uint, uint) {
    return (price, confidence);
  }

  event SpotUpdated(uint price, uint confidence);
}
