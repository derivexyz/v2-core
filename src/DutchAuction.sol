// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./interfaces/IDutchAuction.sol";
import "./interfaces/IPCRM.sol";

contract DutchAuction is IDutchAuction {
  
  mapping(address => bool) public isRiskManagers;
  mapping(bytes32 => AuctionDetails) public auctions;

  constructor() {}

  function addRiskManger() external returns(bool) {
    isRiskManagers[msg.sender] = true;
    return true;
  }
  
  // can only be called by the manager and will initiate an auction
  function startAuction(uint accId) external returns(bytes32) {
    if (!isRiskManagers[msg.sender]) {
      revert NotRiskManager(msg.sender);
    }

    bytes32 auctionId = keccak256(abi.encodePacked(accId, block.timestamp));

    auctions[auctionId] = AuctionDetails({
      accountId: accId,
      upperBound: 0,
      lowerBound: 0
    });
    return auctionId;
  }

  // a user submits a bid for a particular auction
  function bid(uint auctionId, int amount) external returns(uint) {
    // need to check if the timelimit for the auction has been ecplised
    // the position is thus insolvent otherwise


    // add bid
  }

  function auctionDetails(bytes32 auctionId) external view returns(AuctionDetails memory) {
    return auctions[auctionId];
  }

  function currentAuctionPrice(uint auctionId) external view returns(uint) {}

  function endAuction(uint auctionId) external returns(uint) {}

  function getMaxProportion(uint accountId) external returns(uint) {}


  ///////////////
  // internal //
  ///////////////

  function getVMax(uint accountId) internal returns(uint) {
    (IPCRM.ExpiryHolding[] memory expiryHoldings, int cash) = IPCRM(msg.sender).getSortedHoldings(accountId);

    // need to discuss with mech how this is going to work
  } 

  function getVmin(uint accountId) internal returns(uint) {
    // vmin is going to be difficult to compute
  }

  function getCurrentScalar(uint auctionId) internal returns(uint) {
    // need to check if the auction is still ongoing
    // if not then return the lower bound
    // otherwise return using dv 
  }

  ////////////
  // ERRORS //
  ////////////

  error NotRiskManager(address sender);
}