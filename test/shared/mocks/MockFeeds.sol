// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../../src/interfaces/IChainlinkSpotFeed.sol";
import "../../../src/interfaces/ISpotFeed.sol";
import "../../../src/interfaces/IVolFeed.sol";
import "../../../src/interfaces/IDiscountFactorFeed.sol";

contract MockFeeds is ISpotFeed, IVolFeed, IFutureFeed, IDiscountFactorFeed, ISettlementFeed {
  uint public spot;
  uint public last = block.timestamp;
  mapping(uint => uint) expiryPrice;
  mapping(uint => uint) settlementPrice;
  mapping(uint => mapping(uint => uint)) vols;

  function setSpot(uint _spot) external {
    spot = _spot;
    last = block.timestamp;
  }

  function setExpiryPrice(uint expiry, uint price) external {
    expiryPrice[expiry] = price;
  }

  function setSettlementPrice(uint expiry, uint price) external {
    settlementPrice[expiry] = price;
  }

  function setVol(uint strike, uint expiry, uint vol) external {
    vols[strike][expiry] = vol;
  }

  // ISpotFeed

  function getSpot() external view returns (uint, uint) {
    return (spot, 1e18);
  }

  // IFutureFeed

  function getFuturePrice(uint expiry) external view returns (uint futurePrice, uint confidence) {
    return (spot, 1e18);
  }

  // ISettlementPrice

  function getSettlementPrice(uint expiry) external view returns (uint) {
    return expiryPrice[expiry];
  }

  // IVolFeed

  function getVol(uint128 strike, uint128 expiry) external view returns (uint128 vol, uint64 confidence) {
    return (1e18, 1e18);
  }

  // IDiscountFactorFeed
  function getDiscountFactor(uint expiry) external view returns (uint64 discountFactor, uint64 confidence) {
    return (1e18, 1e18);
  }
}
