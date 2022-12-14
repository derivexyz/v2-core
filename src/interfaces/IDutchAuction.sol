// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;


// Interface for Dutch Auction Contract
interface IDutchAuction {

  struct AuctionDetails {
    address account;
    bytes32 auctionId; // hash of the time and the address??
    uint depositedMargin;
    uint intialMargin;
    uint maintenceMargin;
    uint upperBound;
    uint lowerBound;
    uint startBlock;
    uint endBlock;
  }

  struct DutchAuctionParameters {
    uint numSteps;
    address securityModule;
  }

  // can only be called by the manager and will initiate an auction
  function startAuction(AuctionDetails memory auction) external returns(uint);

  // a user submits a bid for a particular auction
  function bid(uint auctionId, uint amount) external returns(uint);

  function auctionDetails(uint auctionId) external view returns(AuctionDetails memory);

  function currentAuctionPrice(uint auctionId) external view returns(uint);

  function currentPercentageOfPortfolioToLiquidate(uint auctionId) external view returns(uint);

  function endAuction(uint auctionId) external returns(uint);

  function getMaxProportion(uint accountId) external returns(uint);
   
  function addRiskManger() external;
}