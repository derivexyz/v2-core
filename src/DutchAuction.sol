// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./interfaces/IDutchAuction.sol";
import "./interfaces/IPCRM.sol";
import "./interfaces/ISpotFeeds.sol";

contract DutchAuction is IDutchAuction {
  
  mapping(address => bool) public isRiskManagers;
  mapping(bytes32 => Auction) public auctions;
  DutchAuctionParameters public parameters;
  ISpotFeeds public spotFeed;

  constructor(ISpotFeeds _spotFeed) {
    spotFeed = _spotFeed;
  }
  
  /// @notice Sets the dutch Auction Parameters
  /// @dev This function is used to set the parameters for the dutch auction
  /// @param params A struct that contains all the parameters for the dutch auction
  /// @return Documents the parameters for the dutch auction that were just set.
  function setDutchAuctionParameters(DutchAuctionParameters memory params) external returns(DutchAuctionParameters memory) {
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
    uint price = spotFeed.getSpot(1);
    int upperBound = getVMax(accountId, int(price));
    int lowerBound = getVmin(accountId, int(price));

    auctions[auctionId] = Auction({
      insolvent: false,
      ongoing: true,
      startBlock: block.number,
      endBlock: block.number + parameters.lengthOfAuction,
      dv: 0,
      auction: AuctionDetails({
      accountId: accountId,
      upperBound: upperBound,
      lowerBound: lowerBound
    })});
    return auctionId;
  }

  /// @notice a user submits a bid for a particular auction
  /// @dev Takes in the auction and returns the account id
  /// @param auctionId the bytesId that corresponds to a particular auction
  /// @return amount the amount as a percantage of the portfolio that the user is willing to purchase
  function bid(bytes32 auctionId, int amount) external returns(uint) {
    // need to check if the timelimit for the auction has been ecplised
    // the position is thus insolvent otherwise
    // need to check if this amount would put the portfolio over is matience marign
    // if so then revert
    
    // send/ take money from the user if depending on the current priec
    // if the user has less margin then the amount they are bidding then get it from the security module

    // add bid
    // IPCRM.executeBid(accountId, msg.sender, amount, cashAmount); // not sure about the liquidator difference

  }

  function auctionDetails(bytes32 auctionId) external view returns(Auction memory) {
    return auctions[auctionId];
  }

  function currentAuctionPrice(uint auctionId) external view returns(uint) {}

  function endAuction(uint auctionId) external returns(uint) {}

  function getMaxProportion(uint accountId) external returns(uint) {}


  ///////////////
  // internal //
  ///////////////

  function getVMax(uint accountId, int spot) internal returns(int) {
    (IPCRM.ExpiryHolding[] memory expiryHoldings, int cash) = IPCRM(msg.sender).getSortedHoldings(accountId);
    int portfolioMargin = cash;
    for (uint i = 0; i < expiryHoldings.length; i++) {
      // iterate over all strike holdings, if they are Long calls mark them to spot, if they are long puts consider them at there strike, shorts to 0
      for (uint j = 0; j < expiryHoldings[i].strikes.length; j++) {
        portfolioMargin += expiryHoldings[i].strikes[j].puts * int64(expiryHoldings[i].strikes[j].strike);
        portfolioMargin += expiryHoldings[i].strikes[j].calls * spot;
      }
    }
    // need to discuss with mech how this is going to work
    return portfolioMargin;
  } 

  function getVmin(uint accountId, int spot) internal returns(int) {

    // TODO: need to do some more work on this. 
    // vmin is going to be difficult to compute
    (IPCRM.ExpiryHolding[] memory expiryHoldings, int cash) = IPCRM(msg.sender).getSortedHoldings(accountId);
    int portfolioMargin = cash;
    for (uint i = 0; i < expiryHoldings.length; i++) {

      // iterate over all strike holdings, if they are Long calls mark them to spot, if they are long puts consider them at there strike, shorts to 0
    
      for (uint j = 0; j < expiryHoldings[i].strikes.length; j++) {
        portfolioMargin += expiryHoldings[i].strikes[j].puts * int64(expiryHoldings[i].strikes[j].strike);
        portfolioMargin += expiryHoldings[i].strikes[j].calls * spot;
      }
    }

    return portfolioMargin;
  }

  function getCurrentBidPrice(bytes32 auctionId) view external returns(int) {
    // need to check if the auction is still ongoing
    // if not then return the lower bound
    // otherwise return using dv 
    Auction memory auction = auctions[auctionId];
    int upperBound = auction.auction.upperBound;
    uint numSteps = block.number / parameters.stepInterval; // will round down to whole number. 

    // dv = (Vmax - Vmin) * numSteps
    return upperBound - int(auction.dv * numSteps);
  }

  ////////////
  // EVENTS //
  ////////////

  // emmited when an auction starts
  event AuctionStarted(bytes32 auctionId, uint accountId, uint upperBound, uint lowerBound);
  
  // emmited when a bid is placed
  event Bid(bytes32 auctionId, address bidder, uint amount);
  
  // emmited when an auction results in insolvency
  event Insolvent(bytes32 auctionId, uint accountId);
  
  // emmited when an auction ends, either by insolvency or by the assets of an account being purchased. 
  event AuctionEnded(bytes32 auctionId, uint accountId, uint amount);


  ////////////
  // ERRORS //
  ////////////

  error NotRiskManager(address sender);
}