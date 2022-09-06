pragma solidity ^0.8.13;

import "synthetix/Owned.sol";
import "src/interfaces/IAbstractAsset.sol";

interface PriceFeeds {
  function assignFeedToAsset(IAbstractAsset asset, uint feedId) external;
  function setSpotForFeed(uint feedId, uint spotPrice) external;
  function getSpotForFeed(uint feedId) external view returns (uint spotPrice);
  function getSpotForAsset(IAbstractAsset asset) external view returns (uint spotPrice);

  function assetToFeedId(IAbstractAsset asset) external view returns (uint feedId);
}

contract TestPriceFeeds is PriceFeeds, Owned {
  mapping(IAbstractAsset => uint) public assetToFeedId; // asset => feedId;
  mapping(uint => uint) spotPrices; // feedId => spotPrice;

  constructor() Owned() {}

  function setSpotForFeed(uint feedId, uint spotPrice) external onlyOwner {
    spotPrices[feedId] = spotPrice;
  }

  function getSpotForFeed(uint feedId) public view returns (uint spotPrice) {
    spotPrice = spotPrices[feedId];
    require(spotPrice != 0, "No spot price for asset");
    return spotPrice;
  }

  function assignFeedToAsset(IAbstractAsset asset, uint feedId) external {
    require(msg.sender == address(asset), "only asset can assign its feed");
    assetToFeedId[asset] = feedId;
  }

  function getSpotForAsset(IAbstractAsset asset) external view override returns (uint spotPrice) {
    return getSpotForFeed(assetToFeedId[asset]);
  }
}
