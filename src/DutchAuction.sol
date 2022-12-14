// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./interfaces/IDutchAuction.sol";

contract DutchAuction is IDutchAuction {

  constructor() {}

  function addRiskManger() external {}
  
  // can only be called by the manager and will initiate an auction
  function startAuction(AuctionDetails memory auction) external returns(uint) {
    
  }

  // a user submits a bid for a particular auction
  function bid(uint auctionId, uint amount) external returns(uint) {}

  function auctionDetails(uint auctionId) external view returns(AuctionDetails memory) {}

  function currentAuctionPrice(uint auctionId) external view returns(uint) {}

  function currentPercentageOfPortfolioToLiquidate(uint auctionId) external view returns(uint) {}

  function endAuction(uint auctionId) external returns(uint) {}

  function getMaxProportion(uint accountId) external returns(uint) {}
}