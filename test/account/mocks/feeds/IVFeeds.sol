// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "synthetix/Owned.sol";
import "src/interfaces/IAsset.sol";

// simple single IV oracle
contract IVFeeds is Owned {
  mapping(IAsset => mapping(uint => uint)) public feedIds; // asset => subId => feedId;
  mapping(uint => uint) IVs; // feedId => iv;

  constructor() Owned() {}

  function setIVForFeed(uint feedId, uint iv) external onlyOwner {
    IVs[feedId] = iv;
  }

  function getIVForFeed(uint feedId) public view returns (uint iv) {
    iv = IVs[feedId];
    require(iv != 0, "No iv set for asset, subId");
    return iv;
  }

  function assignFeedToSubId(IAsset asset, uint subId, uint feedId) external {
    feedIds[asset][subId] = feedId;
  }

  function getIVForSubId(IAsset asset, uint subId) external view returns (uint iv) {
    return getIVForFeed(feedIds[asset][subId]);
  }
}
