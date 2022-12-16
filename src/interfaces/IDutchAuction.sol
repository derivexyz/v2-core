// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;


// Interface for Dutch Auction Contract
interface IDutchAuction {

  struct AuctionDetails {
    uint accountId;
    uint upperBound;
    uint lowerBound;
  }

  struct Auction {
    AuctionDetails auction;
    bool insolvent;
    bool ongoing;
    uint startBlock;
    uint endBlock;
    uint dv; // the amount to decrease by each step
  }

  struct DutchAuctionParameters {
    uint numSteps;
    address securityModule;
  }

  // can only be called by the manager and will initiate an auction
  function startAuction(AuctionDetails memory auction) external returns(bytes32);

  // a user submits a bid for a particular auction
  function bid(uint auctionId, uint amount) external returns(uint);

  // view to get the details on an auction
  function auctionDetails(uint auctionId) external view returns(AuctionDetails memory);

  // gets the current price of an auction bound between Vmax and Vlower
  function currentAuctionPrice(uint auctionId) external view returns(uint);

  // TODO: may not be required anymore
  function getMaxProportion(uint accountId) external returns(uint);

  // adds a risk manager that can initiate auctions
  // may need to check if it is the accounts verified risk manager
  function addRiskManger() external returns(bool);
}