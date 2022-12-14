// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../feeds/PriceFeeds.sol";

// Used by assets to agree on exact price per expiry
contract SettlementPricer {
  struct SettlementDetails {
    uint price;
    uint timeSet;
  }

  PriceFeeds priceFeeds;
  mapping(uint => mapping(uint => SettlementDetails)) settlementDetails; // feedId => expiry timestamp => settlementPrice

  constructor(PriceFeeds _feeds) {
    priceFeeds = _feeds;
  }

  // Determining settlement price could be done via a "race" to get to the price first, so just use the first price found
  // as soon as expiry is hit. Otherwise you could do a bidding mechainsm for things like "price closest to expiry" or
  // you could grab a twap of the price from uniswap around the expiry
  function setSettlementPrice(uint feedId, uint expiry) external {
    require(settlementDetails[feedId][expiry].price == 0, "settlement price already set");
    require(block.timestamp >= expiry, "expiry not reached");
    settlementDetails[feedId][expiry] =
      SettlementDetails({price: priceFeeds.getSpotForFeed(feedId), timeSet: block.timestamp});
  }

  function maybeGetSettlementDetails(uint feedId, uint expiry) external view returns (SettlementDetails memory) {
    return settlementDetails[feedId][expiry];
  }

  function getSettlementDetails(uint feedId, uint expiry) public view returns (SettlementDetails memory) {
    require(settlementDetails[feedId][expiry].price != 0, "settlement price not set");
    return settlementDetails[feedId][expiry];
  }

  function getSettlementDetailsForAsset(IAsset asset, uint expiry) external view returns (SettlementDetails memory) {
    return getSettlementDetails(priceFeeds.assetToFeedId(asset), expiry);
  }

  // add in a function prefixed with test here to prevent coverage from picking it up.
  function test() public {}
}
