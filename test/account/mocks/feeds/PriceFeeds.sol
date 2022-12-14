// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "synthetix/Owned.sol";
import "src/interfaces/IAsset.sol";

interface PriceFeeds {
    function assignFeedToAsset(IAsset asset, uint256 feedId) external;
    function setSpotForFeed(uint256 feedId, uint256 spotPrice) external;
    function getSpotForFeed(uint256 feedId)
        external
        view
        returns (uint256 spotPrice);
    function getSpotForAsset(IAsset asset)
        external
        view
        returns (uint256 spotPrice);

    function assetToFeedId(IAsset asset)
        external
        view
        returns (uint256 feedId);
}

contract TestPriceFeeds is PriceFeeds, Owned {
    mapping(IAsset => uint256) public assetToFeedId; // asset => feedId;
    mapping(uint256 => uint256) spotPrices; // feedId => spotPrice;

    constructor() Owned() {}

    function setSpotForFeed(uint256 feedId, uint256 spotPrice)
        external
        onlyOwner
    {
        spotPrices[feedId] = spotPrice;
    }

    function getSpotForFeed(uint256 feedId)
        public
        view
        returns (uint256 spotPrice)
    {
        spotPrice = spotPrices[feedId];
        require(spotPrice != 0, "No spot price for asset");
        return spotPrice;
    }

    function assignFeedToAsset(IAsset asset, uint256 feedId) external {
        require(msg.sender == address(asset), "only asset can assign its feed");
        assetToFeedId[asset] = feedId;
    }

    function getSpotForAsset(IAsset asset)
        external
        view
        override
        returns (uint256 spotPrice)
    {
        return getSpotForFeed(assetToFeedId[asset]);
    }
}
