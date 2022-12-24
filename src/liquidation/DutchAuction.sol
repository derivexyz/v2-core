// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../interfaces/IPCRM.sol";
import "../interfaces/ISpotFeeds.sol";
import "../libraries/synthetix/Owned.sol";

contract DutchAuction is Owned {
  struct AuctionDetails {
    uint accountId;
    int upperBound;
    int lowerBound;
  }

  struct Auction {
    AuctionDetails auction;
    bool insolvent;
    bool ongoing;
    uint startTime;
    uint endTime;
    uint dv; // TODO: mech says that this can be calculated once but potential issue with spot changing, the amount to decrease by each step
  }

  struct DutchAuctionParameters {
    uint stepInterval;
    uint lengthOfAuction;
    address securityModule;
  }

  IPCRM public riskManager;
  mapping(bytes32 => Auction) public auctions;
  DutchAuctionParameters public parameters;
  ISpotFeeds public spotFeed;

  constructor(ISpotFeeds _spotFeed, address _riskManager) Owned() {
    spotFeed = _spotFeed;
    riskManager = IPCRM(_riskManager);
  }

  /// @notice Sets the dutch Auction Parameters
  /// @dev This function is used to set the parameters for the dutch auction
  /// @param params A struct that contains all the parameters for the dutch auction
  /// @return Documents the parameters for the dutch auction that were just set.
  // TODO: needs to be rescrited to owner
  function setDutchAuctionParameters(DutchAuctionParameters memory params)
    external
    _onlyOwner()
    returns (DutchAuctionParameters memory)
  {
    // set the parameters for the dutch auction
    parameters = params;
    return parameters;
  }

  /// @notice Called by the riskManager to start an auction
  /// @dev Can only be auctioned by a risk manager and will start an auction
  /// @param accountId The id of the account being liquidated
  /// @return bytes32 the id of the auction that was just started
  function startAuction(uint accountId) external returns (bytes32) {
    if (address(riskManager) != msg.sender) {
      revert DA_NotRiskManager(msg.sender);
    }

    //TODO: finish this function

    bytes32 auctionId = keccak256(abi.encodePacked(accountId, block.timestamp));
    uint price = spotFeed.getSpot(1);
    (int upperBound) = getVMax(accountId, int(price));
    (int lowerBound) = getVmin(accountId, int(price));

    auctions[auctionId] = Auction({
      insolvent: false,
      ongoing: true,
      startTime: block.timestamp,
      endTime: block.timestamp + parameters.lengthOfAuction,
      dv: 0, // TODO: need to be able to calculate dv
      auction: AuctionDetails({accountId: accountId, upperBound: upperBound, lowerBound: lowerBound})
    });
    return auctionId;
  }

  /// @notice a user submits a bid for a particular auction
  /// @dev Takes in the auction and returns the account id
  /// @param auctionId the bytesId that corresponds to a particular auction
  /// @return amount the amount as a percantage of the portfolio that the user is willing to purchase
  function bid(bytes32 auctionId, int amount) external returns (uint) {
    // need to check if the timelimit for the auction has been ecplised
    // the position is thus insolvent otherwise
    // need to check if this amount would put the portfolio over is matience marign
    // if so then revert

    // send/ take money from the user if depending on the current priec
    // if the user has less margin then the amount they are bidding then get it from the security module

    // add bid
    // IPCRM.executeBid(accountId, msg.sender, amount, cashAmount); // not sure about the liquidator difference
  }

  /// @notice returns the details of an ongoing auction
  /// @param auctionId the id of the auction that is being queried
  /// @return Auction returns the struct of the auction details
  function auctionDetails(bytes32 auctionId) external view returns (Auction memory) {
    return auctions[auctionId];
  }

  /// @notice Gets the maximum size of the portfolio that could be bought at the current price
  /// @param accountId the id of the account being liquidated
  /// @return uint the proportion of the portfolio that could be bought at the current price
  function getMaxProportion(uint accountId) external returns (uint) {}

  ///////////////
  // internal //
  ///////////////

  /// @notice gets the upper bound for the liquidation price
  /// @dev requires the accountId and the spot price to mark each asset at a particular value
  /// @param accountId the accountId of the account that is being liquidated
  /// @return spot the spot price of the asset, TODO: consider how this is going to work with options on different spot markets.
  function getVMax(uint accountId, int spot) internal returns (int) {
    // (IPCRM.ExpiryHolding[] memory expiryHoldings, int cash) = IPCRM(msg.sender).getSortedHoldings(accountId);
    // int portfolioMargin = cash;
    // for (uint i = 0; i < expiryHoldings.length; i++) {
    //   // iterate over all strike holdings, if they are Long calls mark them to spot, if they are long puts consider them at there strike, shorts to 0
    //   for (uint j = 0; j < expiryHoldings[i].strikes.length; j++) {
    //     portfolioMargin += expiryHoldings[i].strikes[j].puts * int64(expiryHoldings[i].strikes[j].strike);
    //     portfolioMargin += expiryHoldings[i].strikes[j].calls * spot;
    //   }
    // }
    // // need to discuss with mech how this is going to work
    // return portfolioMargin;
    return 0;
  }

  /// @notice gets the lower bound for the liquidation price
  /// @dev requires the accountId and the spot price to mark each asset at a particular value
  /// @param accountId the accountId of the account that is being liquidated
  /// @return spot the spot price of the asset, TODO: consider how this is going to work with options on different spot markets.
  function getVmin(uint accountId, int spot) internal returns (int) {
    // TODO: need to do some more work on this.
    // vmin is going to be difficult to compute
    // (IPCRM.ExpiryHolding[] memory expiryHoldings, int cash) = IPCRM(msg.sender).getSortedHoldings(accountId);
    // int portfolioMargin = cash;
    // for (uint i = 0; i < expiryHoldings.length; i++) {

    //   // iterate over all strike holdings, if they are Long calls mark them to spot, if they are long puts consider them at there strike, shorts to 0

    //   for (uint j = 0; j < expiryHoldings[i].strikes.length; j++) {
    //     portfolioMargin += expiryHoldings[i].strikes[j].puts * int64(expiryHoldings[i].strikes[j].strike);
    //     portfolioMargin += expiryHoldings[i].strikes[j].calls * spot;
    //   }
    // }

    // return portfolioMargin;
    return 0;
  }

  /// @notice gets the current bid price for a particular auction at the current block
  /// @dev returns the current bid price for a particular auction
  /// @param auctionId the bytes32 id of an auctionId
  /// @return int the current bid price for the auction
  function getCurrentBidPrice(bytes32 auctionId) external view returns (int) {
    // need to check if the auction is still ongoing
    // if not then return the lower bound
    // otherwise return using dv
    Auction memory auction = auctions[auctionId];
    int upperBound = auction.auction.upperBound;
    uint numSteps = block.timestamp / parameters.stepInterval; // will round down to whole number.

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

  error DA_NotRiskManager(address sender);
}
