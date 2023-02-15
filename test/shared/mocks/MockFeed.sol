// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../../../src/interfaces/IChainlinkSpotFeed.sol";

contract MockFeed is IChainlinkSpotFeed {
  uint public spot;
  uint public last = block.timestamp;
  mapping(uint => uint) expiryPrice;

  function setSpot(uint _spot) external returns (uint) {
    spot = _spot;
    last = block.timestamp;
    return spot;
  }

  function getFuturePrice(uint)
    /**
     * expiry*
     */
    external
    view
    returns (uint)
  {
    return spot;
  }

  function getSpot() external view returns (uint) {
    return spot;
  }

  function getSpotAndUpdatedAt() external view returns (uint, uint) {
    return (spot, last);
  }

  function getSettlementPrice(uint expiry) external view returns (uint) {
    return expiryPrice[expiry];
  }

  function setFuturePrice(uint expiry, uint price) external {
    expiryPrice[expiry] = price;
  }

  function test() public {}
}
