// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "src/interfaces/ISpotFeed.sol";
import "src/interfaces/IVolFeed.sol";
import "src/interfaces/IInterestRateFeed.sol";
import "src/interfaces/IForwardFeed.sol";
import "src/interfaces/ISettlementFeed.sol";

import "src/interfaces/IDataReceiver.sol";
import "src/interfaces/IAllowList.sol";

contract MockFeeds is ISpotFeed, IVolFeed, IForwardFeed, IInterestRateFeed, ISettlementFeed, IDataReceiver, IAllowList {
  uint public spot;
  uint public spotConfidence;
  mapping(uint => uint) forwardPrices;
  mapping(uint => uint) fwdFixedPortion;
  mapping(uint => uint) forwardPriceConfidences;
  mapping(uint => int) interestRates;
  mapping(uint => uint) interestRateConfidences;
  mapping(uint => uint) settlementPrice;
  mapping(uint64 => mapping(uint128 => uint)) vols;
  mapping(uint64 => uint) volConfidences;
  mapping(address => bool) public canTrade;

  function setCanTrade(address account, bool _canTrade) external {
    canTrade[account] = _canTrade;
  }

  function setSpot(uint _spot, uint _confidence) external {
    spot = _spot;
    spotConfidence = _confidence;
  }

  function setSettlementPrice(uint expiry, uint price) external {
    settlementPrice[expiry] = price;
  }

  function setVol(uint64 expiry, uint128 strike, uint vol, uint confidence) external {
    vols[expiry][strike] = vol;
    volConfidences[expiry] = confidence;
  }

  function setVolConfidence(uint64 expiry, uint confidence) external {
    volConfidences[expiry] = confidence;
  }

  function getExpiryMinConfidence(uint64 expiry) external view returns (uint) {
    return volConfidences[expiry];
  }

  function setForwardPrice(uint expiry, uint price, uint confidence) external {
    forwardPrices[expiry] = price;
    fwdFixedPortion[expiry] = 0;
    forwardPriceConfidences[expiry] = confidence;
  }

  function setForwardPricePortions(uint expiry, uint fixedPortion, uint price, uint confidence) external {
    forwardPrices[expiry] = price;
    fwdFixedPortion[expiry] = fixedPortion;
    forwardPriceConfidences[expiry] = confidence;
  }

  function setInterestRate(uint expiry, int96 rate, uint64 confidence) external {
    interestRates[expiry] = rate;
    interestRateConfidences[expiry] = confidence;
  }

  function acceptData(bytes calldata callData) external override {
    spot = abi.decode(callData, (uint));
  }

  // ISpotFeed

  function getSpot() external view returns (uint, uint) {
    return (spot, spotConfidence);
  }

  // IForwardFeed

  function getForwardPrice(uint64 expiry) external view returns (uint forwardPrice, uint confidence) {
    return (forwardPrices[expiry] + fwdFixedPortion[expiry], forwardPriceConfidences[expiry]);
  }

  function getForwardPricePortions(uint64 expiry)
    external
    view
    returns (uint forwardFixedPortion, uint forwardVariablePortion, uint confidence)
  {
    return (fwdFixedPortion[expiry], forwardPrices[expiry], forwardPriceConfidences[expiry]);
  }

  // ISettlementPrice

  function getSettlementPrice(uint64 expiry) external view returns (bool, uint) {
    return (settlementPrice[expiry] != 0, settlementPrice[expiry]);
  }

  // IVolFeed

  function getVol(uint128 strike, uint64 expiry) external view returns (uint vol, uint confidence) {
    return (vols[expiry][strike], volConfidences[expiry]);
  }

  // IInterestRateFeed
  function getInterestRate(uint64 expiry) external view returns (int interestRate, uint confidence) {
    return (interestRates[expiry], interestRateConfidences[expiry]);
  }
}
