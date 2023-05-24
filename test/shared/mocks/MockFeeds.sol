// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "src/interfaces/ISpotFeed.sol";
import "src/interfaces/IVolFeed.sol";
import "src/interfaces/IInterestRateFeed.sol";
import "src/interfaces/IForwardFeed.sol";
import "src/interfaces/ISettlementFeed.sol";

import "src/interfaces/IDataReceiver.sol";
import "../../../src/interfaces/ISpotDiffFeed.sol";

contract MockFeeds is
  ISpotFeed,
  IVolFeed,
  IForwardFeed,
  IInterestRateFeed,
  ISettlementFeed,
  ISpotDiffFeed,
  IDataReceiver
{
  uint public spot;
  uint public spotConfidence;
  int128 public spotDiff;
  uint64 public spotDiffConfidence;
  mapping(uint => uint) forwardPrices;
  mapping(uint => uint) forwardPriceConfidences;
  mapping(uint => int64) interestRates;
  mapping(uint => uint64) interestRateConfidences;
  mapping(uint => uint) settlementPrice;
  mapping(uint64 => mapping(uint128 => uint128)) vols;
  mapping(uint64 => mapping(uint128 => uint64)) volConfidences;

  function setSpot(uint _spot, uint _confidence) external {
    spot = _spot;
    spotConfidence = _confidence;
  }

  function setSpotDiff(int128 _spotDiff, uint64 _confidence) external {
    spotDiff = _spotDiff;
    spotDiffConfidence = _confidence;
  }

  function setSettlementPrice(uint expiry, uint price) external {
    settlementPrice[expiry] = price;
  }

  function setVol(uint64 expiry, uint128 strike, uint128 vol, uint64 confidence) external {
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

  function acceptData(bytes calldata callData) external override {
    spot = abi.decode(callData, (uint));
  }

  // ISpotFeed

  function getSpot() external view returns (uint, uint) {
    return (spot, spotConfidence);
  }

  // ISpotDiffFeed

  function getSpotDiff() external view returns (int128, uint64) {
    return (spotDiff, spotDiffConfidence);
  }

  // IForwardFeed

  function getForwardPrice(uint64 expiry) external view returns (uint forwardPrice, uint confidence) {
    return (forwardPrices[expiry], forwardPriceConfidences[expiry]);
  }

  function getForwardPricePortions(uint64 expiry)
    external
    view
    returns (uint forwardFixedPortion, uint forwardVariablePortion, uint confidence)
  {
    return (0, forwardPrices[expiry], forwardPriceConfidences[expiry]);
  }

  // ISettlementPrice

  function getSettlementPrice(uint64 expiry) external view returns (uint) {
    return settlementPrice[expiry];
  }

  // IVolFeed

  function getVol(uint128 strike, uint64 expiry) external view returns (uint128 vol, uint64 confidence) {
    return (vols[expiry][strike], volConfidences[expiry][strike]);
  }

  // IInterestRateFeed
  function getInterestRate(uint64 expiry) external view returns (int64 interestRate, uint64 confidence) {
    return (interestRates[expiry], interestRateConfidences[expiry]);
  }
}
