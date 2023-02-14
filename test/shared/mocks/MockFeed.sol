// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../../../src/interfaces/IFutureFeed.sol";
import "../../../src/interfaces/ISettlementFeed.sol";

contract MockFeed is IFutureFeed, ISettlementFeed {
  uint public spot;
  mapping(uint => uint) expiryPrice;

  function setSpot(uint _spot) external returns (uint) {
    spot = _spot;
    return spot;
  }

  function getFuturePrice(uint) external view returns (uint) {
    return spot;
  }

  function getSettlementPrice(uint expiry) external view returns (uint) {}

  function setFuturePrice(uint expiry, uint price) external {
    expiryPrice[expiry] = price;
  }

  function test() public {}
}
