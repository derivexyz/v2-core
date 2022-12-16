// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./interfaces/IDutchAuction.sol";
import "./interfaces/IPCRM.sol";

contract DutchAuction is IDutchAuction {
  
  mapping(address => bool) public isRiskManagers;
  mapping(bytes32 => Auction) public auctions;
  DutchAuction public parameters;

  constructor() {}
  
  /// @notice Sets the dutch Auction Parameters
  /// @dev This function is used to set the parameters for the dutch auction
  /// @param params A struct that contains all the parameters for the dutch auction
  /// @return Documents the parameters for the dutch auction that were just set.
  function setDutchAuctionParameters(DutchAuctionParameters memory params) external returns(DutchAuction memory) {
    // set the parameters for the dutch auction
    parameters = params;
    return parameters;
  }

  // adds a risk manager that can initiate auctions
  function addRiskManger() external returns(bool) {
    isRiskManagers[msg.sender] = true;
    return true;
  }
  
  // can only be called by the manager and will initiate an auction
  function startAuction(uint accountId) external returns(bytes32) {
    if (!isRiskManagers[msg.sender]) {
      revert NotRiskManager(msg.sender);
    }

    bytes32 auctionId = keccak256(abi.encodePacked(accountId, block.timestamp));

    auctions[auctionId] = AuctionDetails({
      accountId: accountId,
      upperBound: 0,
      lowerBound: 0
    });
    return auctionId;
  }

  /// @notice a user submits a bid for a particular auction
  /// @dev Takes in the auction and returns the account id
  /// @param auctionId the bytesId that corresponds to a particular auction
  /// @return Documents the amount as a percantage of the portfolio that the user is willing to purchase
  function bid(bytes auctionId, int amount) external returns(uint) {
    // need to check if the timelimit for the auction has been ecplised
    // the position is thus insolvent otherwise
    // need to check if this amount would put the portfolio over is matience marign
    // if so then revert
    
    // send/ take money from the user if depending on the current priec
    // if the user has less margin then the amount they are bidding then get it from the security module

    // add bid
    IPCRM.executeBid(accountId, liquidatorId, portion, cashAmount); // not sure about the liquidator difference

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
    uint portfolioMargin = cash;
    for (uint i = 0; i < expiryHoldings.length; i++) {
      // iterate over all strike holdings, if they are Long calls mark them to spot, if they are long puts consider them at there strike, shorts to 0
      for (uint j = 0; j < expiryHoldings[i].strikes.length; j++) {
        portfolioMargin += expiryHoldings[i].strikes[j].puts * expiryHoldings[i].strikes[j].strike;
        uint spot = IPCRM(msg.sender).getSpotPrice(expiryHoldings[i].expiry); // TODO: get spot.
        portfolioMargin += expiryHoldings[i].strikes[j].calls * spot;
      }
    }
    // need to discuss with mech how this is going to work
  } 

  function getVmin(uint accountId) internal returns(uint) {
    // vmin is going to be difficult to compute
    (IPCRM.ExpiryHolding[] memory expiryHoldings, int cash) = IPCRM(msg.sender).getSortedHoldings(accountId);
    uint portfolioMargin = cash;
    for (uint i = 0; i < expiryHoldings.length; i++) {
      // iterate over all strike holdings, if they are Long calls mark them to spot, if they are long puts consider them at there strike, shorts to 0
      for (uint j = 0; j < expiryHoldings[i].strikes.length; j++) {
        portfolioMargin += expiryHoldings[i].strikes[j].puts * expiryHoldings[i].strikes[j].strike;
        uint spot = IPCRM(msg.sender).getSpotPrice(expiryHoldings[i].expiry); // TODO: get spot.
        portfolioMargin += expiryHoldings[i].strikes[j].calls * spot;
      }
    }
  }

  function getCurrentBidPrice(bytes auctionId) internal returns(uint) {
    // need to check if the auction is still ongoing
    // if not then return the lower bound
    // otherwise return using dv 
    Auction auction = auctions[auctionId];
    uint upperBound = auction.upperBound;
    uint numSteps = parameters.numSteps;

    // dv = (Vmax - Vmin) * numSteps
    return upperBound - auction.dv * numSteps;
  }

  ////////////
  // ERRORS //
  ////////////

  error NotRiskManager(address sender);
}