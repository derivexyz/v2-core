// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./interfaces/IDutchAuction.sol";

contract DutchAuction is IDutchAuction {

  mapping(address => bool) public isRiskManagers;
  mapping(bytes32 => AuctionDetails) public auctions;

  constructor() {}

  function addRiskManger() external returns(bool) {
    isRiskManagers[msg.sender] = true;
    return true;
  }
  
  // can only be called by the manager and will initiate an auction
  function startAuction(AuctionDetails memory auction) external returns(bytes32) {
    if (!isRiskManagers[msg.sender]) {
      revert NotRiskManager(msg.sender);
    }

    bytes32 auctionId = keccak256(auction.accountId + block.timestamp);
    auctions[auctionId] = auction;
    return auctionId;
  }

  // a user submits a bid for a particular auction
  function bid(uint auctionId, int amount) external returns(uint) {}

  function auctionDetails(bytes32 auctionId) external view returns(AuctionDetails memory) {
    return auctions[auctionId];
  }

  function currentAuctionPrice(uint auctionId) external view returns(uint) {}

  function endAuction(uint auctionId) external returns(uint) {}

  function getMaxProportion(uint accountId) external returns(uint) {}

  ////////////
  // ERRORS //
  ////////////

  error NotRiskManager(address sender);
}