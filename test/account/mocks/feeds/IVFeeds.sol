// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "openzeppelin/access/Ownable2Step.sol";
import {IAsset} from "src/interfaces/IAsset.sol";

// simple single IV oracle
contract IVFeeds is Ownable2Step {
  mapping(IAsset => mapping(uint => uint)) public feedIds; // asset => subId => feedId;
  mapping(uint => uint) IVs; // feedId => iv;

  constructor() Ownable2Step() {}

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

  // add in a function prefixed with test here to prevent coverage from picking it up.
  function test() public {}
}
