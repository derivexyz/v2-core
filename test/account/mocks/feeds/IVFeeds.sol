// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "synthetix/Owned.sol";
import "src/interfaces/IAsset.sol";

// simple single IV oracle
contract IVFeeds is Owned {
    mapping(IAsset => mapping(uint256 => uint256)) public feedIds; // asset => subId => feedId;
    mapping(uint256 => uint256) IVs; // feedId => iv;

    constructor() Owned() {}

    function setIVForFeed(uint256 feedId, uint256 iv) external onlyOwner {
        IVs[feedId] = iv;
    }

    function getIVForFeed(uint256 feedId) public view returns (uint256 iv) {
        iv = IVs[feedId];
        require(iv != 0, "No iv set for asset, subId");
        return iv;
    }

    function assignFeedToSubId(IAsset asset, uint256 subId, uint256 feedId)
        external
    {
        feedIds[asset][subId] = feedId;
    }

    function getIVForSubId(IAsset asset, uint256 subId)
        external
        view
        returns (uint256 iv)
    {
        return getIVForFeed(feedIds[asset][subId]);
    }
}
