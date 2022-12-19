// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../../../src/interfaces/ISpotFeeds.sol";


contract MockFeed is ISpotFeeds {

  uint public spot;

  function setSpot(uint _spot) external returns(uint) {
    spot = _spot;
    return spot;
  }

  function getSpot(uint) external view override returns (uint) {
    return spot;
  }

  function getSymbol(uint feedId) external view returns (bytes32) {
    return bytes32("eth/usdc");
  }
}