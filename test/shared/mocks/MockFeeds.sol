// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../../src/interfaces/ISpotFeed.sol";
import "../../../src/interfaces/IVolFeed.sol";
import "../../../src/interfaces/IInterestRateFeed.sol";
import "../../../src/interfaces/IForwardFeed.sol";
import "../../../src/interfaces/ISettlementFeed.sol";

contract MockFeeds is ISpotFeed, IVolFeed, IForwardFeed, IInterestRateFeed, ISettlementFeed {
  uint public spot;
  uint public spotConfidence;
  mapping(uint => uint) forwardPrices;
  mapping(uint => uint) forwardPriceConfidences;
  mapping(uint => int64) interestRates;
  mapping(uint => uint64) interestRateConfidences;
  mapping(uint => uint) settlementPrice;
  mapping(uint128 => mapping(uint128 => uint128)) vols;
  mapping(uint128 => mapping(uint128 => uint64)) volConfidences;

  function setSpot(uint _spot, uint _confidence) external {
    spot = _spot;
    spotConfidence = _confidence;
  }

  function setSettlementPrice(uint expiry, uint price) external {
    settlementPrice[expiry] = price;
  }

  function setVol(uint128 expiry, uint128 strike, uint128 vol, uint64 confidence) external {
    vols[expiry][strike] = vol;
    volConfidences[expiry][strike] = confidence;
  }

  function setForwardPrice(uint expiry, uint price, uint confidence) external {
    forwardPrices[expiry] = price;
    forwardPriceConfidences[expiry] = confidence;
  }

  function setInterestRate(uint expiry, int64 factor, uint64 confidence) external {
    interestRates[expiry] = factor;
    interestRateConfidences[expiry] = confidence;
  }

  // ISpotFeed

  function getSpot() external view returns (uint, uint) {
    return (spot, spotConfidence);
  }

  // IForwardFeed

  function getForwardPrice(uint expiry) external view returns (uint forwardPrice, uint confidence) {
    return (forwardPrices[expiry], forwardPriceConfidences[expiry]);
  }

  // ISettlementPrice

  function getSettlementPrice(uint expiry) external view returns (uint) {
    return settlementPrice[expiry];
  }

  // IVolFeed

  function getVol(uint128 strike, uint128 expiry) external view returns (uint128 vol, uint64 confidence) {
    return (vols[expiry][strike], volConfidences[expiry][strike]);
  }

  // IInterestRateFeed
  function getInterestRate(uint expiry) external view returns (int64 interestRate, uint64 confidence) {
    return (interestRates[expiry], interestRateConfidences[expiry]);
  }
}