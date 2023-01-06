// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// interfaces
import "../interfaces/IPCRM.sol";
import "../interfaces/IDutchAuction.sol";

// inherited
import "synthetix/Owned.sol";
import "openzeppelin/utils/math/SafeMath.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/math/SignedMath.sol";

import "forge-std/Test.sol";

/**
 * @title Dutch Auction
 * @author Lyra
 * @notice Is used to liquidate an account that does not meet the margin requirements
 * 1. The auction is started by the risk Manager
 * 2. Bids are taken in a descending fashion until the matinance margin
 * 3. A scalar is applied to the assets of the portfolio and are transfered to the bidder
 * 4. This continues until matienance margin is met or until the portofolio is declared as insolvent
 * where the security module will step into to handle the risk
 * @dev This contract has a 1 to 1 relationship with a particular risk manager.
 */
contract DutchAuction is IDutchAuction, Owned {
  uint UNIT = 1e18;

  struct AuctionDetails {
    /// the accountId that is being liquidated
    uint accountId;
    /// The upperBound(starting price) of the auction in cash asset
    int upperBound;
    /// The lowerBound(ending price) of the auction in cash asset
    int lowerBound;
  }

  struct Auction {
    /// struct that references the auction details
    AuctionDetails auction;
    /// Boolean that will be switched when the auction price passes through 0
    bool insolvent;
    /// If an auction is active
    bool ongoing;
    /// The startTime of the auction
    uint startTime;
    /// The endTime of the auction
    uint endTime;
    /// The change in value of the portfolio per step in dollars when not insolvent
    uint dv;
  }

  struct DutchAuctionParameters {
    /// Length of each step in seconds
    uint stepInterval;
    /// Total length of an auction in seconds
    uint lengthOfAuction;
    /// The address of the security module
    address securityModule;
  }

  /// @dev AccountId => Auction for when an auction is started
  mapping(uint => Auction) public auctions;

  /// @dev accountId => auctionOwner :TODO: for the risk manager that started the auction??
  mapping(uint => address) public auctionOwner;

  /// @dev The risk manager that is the parent of the dutch auction contract
  IPCRM public immutable riskManager;

  /// @dev The parameters for the dutch auction
  DutchAuctionParameters private parameters;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(address _riskManager) Owned() {
    riskManager = IPCRM(_riskManager);
  }

  /**
   * @notice Sets the dutch Auction Parameters
   * @dev This function is used to set the parameters for the dutch auction
   * @param _parameters A struct that contains all the parameters for the dutch auction
   * @return Documents the parameters for the dutch auction that were just set.
   */
  function setDutchAuctionParameters(DutchAuctionParameters memory _parameters)
    external
    onlyOwner
    returns (DutchAuctionParameters memory)
  {
    // set the parameters for the dutch auction
    parameters = _parameters;
    return parameters;
  }

  /**
   * @notice Called by the riskManager to start an auction
   * @dev Can only be auctioned by a risk manager and will start an auction
   * @param accountId The id of the account being liquidated
   */
  function startAuction(uint accountId) external {
    if (address(riskManager) != msg.sender) {
      revert DA_NotRiskManager();
    }

    if (auctions[accountId].ongoing) {
      revert DA_AuctionAlreadyStarted(accountId);
    }

    uint spot = riskManager.getSpot();

    (int upperBound, int lowerBound) = _getBounds(accountId, int(spot));

    uint dv = _abs(upperBound) / parameters.lengthOfAuction; // as the auction starts in the positive, recalculate when insolvency occurs

    auctions[accountId] = Auction({
      insolvent: false,
      ongoing: true,
      startTime: block.timestamp,
      endTime: block.timestamp + parameters.lengthOfAuction,
      dv: dv,
      auction: AuctionDetails({accountId: accountId, upperBound: upperBound, lowerBound: lowerBound})
    });
  }

  /**
   * @notice a user submits a bid for a particular auction
   * @dev Takes in the auction and returns the account id
   * @param accountId the bytesId that corresponds to the auction being marked as liquidatable
   * @return amount the amount as a percantage of the portfolio that the user is willing to purchase
   */
  function markAsInsolventLiquidation(uint accountId) external returns (bool) {
    if (address(riskManager) != msg.sender) {
      revert DA_NotRiskManager();
    }

    if (_getCurrentBidPrice(accountId) != 0) {
      revert DA_AuctionNotEnteredInsolvency(accountId);
    }
    auctions[accountId].insolvent = true;
    auctions[accountId].dv = _abs(auctions[accountId].auction.lowerBound) / parameters.lengthOfAuction;

    return auctions[accountId].insolvent;
  }

  /**
   * @notice a user submits a bid for a particular auction
   * @dev Takes in the auction and returns the account id
   * @param accountId the bytesId that corresponds to a particular auction
   * @return amount the amount as a percantage of the portfolio that the user is willing to purchase
   */
  function bid(uint accountId, int amount) external returns (uint) {
    // need to check if the timelimit for the auction has been ecplised
    // the position is thus insolvent otherwise
    // need to check if this amount would put the portfolio over is matience marign
    // if so then revert

    // send/ take money from the user if depending on the current priec

    // if the user has less margin then the amount they are bidding then get it from the security module

    // add bid
    // IPCRM.executeBid(accountId, msg.sender, amount, cashAmount); // not sure about the liquidator difference
  }

  /**
   * @notice returns the details of an ongoing auction
   * @param accountId the id of the auction that is being queried
   * @return Auction returns the struct of the auction details
   */
  function getAuctionDetails(uint accountId) external view returns (Auction memory) {
    return auctions[accountId];
  }

  /**
   * @notice Gets the maximum size of the portfolio that could be bought at the current price
   * @param accountId the id of the account being liquidated
   * @return uint the proportion of the portfolio that could be bought at the current price
   */
  function getMaxProportion(uint accountId) external returns (uint) {
    int initialMargin = riskManager.getInitialMargin(accountId);
    int currentBidPrice = _getCurrentBidPrice(accountId);
    uint fMax = SafeCast.toUint256(initialMargin / (initialMargin - currentBidPrice));
    if (fMax > UNIT) {
      return UNIT;
    } else if (currentBidPrice <= 0) {
      return UNIT;
    } else {
      return fMax;
    }
  }

  /**
   * @notice gets the upper bound for the liquidation price
   * @dev requires the accountId and the spot price to mark each asset at a particular value
   * @param accountId the accountId of the account that is being liquidated
   * @param spot the spot price of the asset,
   */
  function getBounds(uint accountId, int spot) external view returns (int, int) {
    return _getBounds(accountId, spot);
  }

  /**
   * @notice gets the current bid price for a particular auction at the current block
   * @dev returns the current bid price for a particular auction
   * @param accountId the bytes32 id of an auctionId
   * @return int the current bid price for the auction
   */
  function getCurrentBidPrice(uint accountId) external view returns (int) {
    return _getCurrentBidPrice(accountId);
  }

  /*
    * @notice gets the parameters for the dutch auction
    * @dev returns the parameters for the dutch auction
    * @return DutchAuctionParameters the parameters for the dutch auction
   */
  function getParameters() external view returns (DutchAuctionParameters memory) {
    return parameters;
  }

  ///////////////
  // internal //
  ///////////////

  /**
   * @notice gets the upper bound for the liquidation price
   * @dev requires the accountId and the spot price to mark each asset at a particular value
   * @param accountId the accountId of the account that is being liquidated
   * @param spot the spot price of the asset,
   */
  function _getBounds(uint accountId, int spot) internal view returns (int maximum, int minimum) {
    IPCRM.ExpiryHolding[] memory expiryHoldings = riskManager.getGroupedHoldings(accountId);
    int cash = riskManager.getCashAmount(accountId);
    maximum += cash;
    minimum += cash;

    for (uint i = 0; i < expiryHoldings.length; i++) {
      // iterate over all strike holdings, if they are Long calls mark them to spot, if they are long puts consider them at there strike, shorts to 0
      (int max, int min) = _markStrike(expiryHoldings[i].strikes, spot);
      maximum += max;
      minimum += min;
    }
  }

  /**
   * @notice calculates the maximum and minimum value of a strike at a particular price
   * @param strikes the strikes that are being marked
   * @param spot the spot price of the asset
   * @dev returns the minimum and maximum value of a strike at a particular price
   */
  function _markStrike(IPCRM.StrikeHolding[] memory strikes, int spot) internal pure returns (int max, int min) {
    for (uint j = 0; j < strikes.length; j++) {
      // calls
      {
        int numCalls = strikes[j].calls;
        max += SignedMath.max(numCalls, 0) * spot;
        min += SignedMath.min(numCalls, 0) * spot;
        // puts
        int numPuts = strikes[j].puts;
        max += SignedMath.max(numPuts, 0) * int64(strikes[j].strike);
        min += SignedMath.min(numPuts, 0) * int64(strikes[j].strike);
      }
    }
    return (max, min);
  }

  /**
   * @notice gets the current bid price for a particular auction at the current block
   * @dev returns the current bid price for a particular auction
   * @param accountId the bytes32 id of an auctionId
   * @return int the current bid price for the auction
   */
  function _getCurrentBidPrice(uint accountId) internal view returns (int) {
    // need to check if the auction is still ongoing
    // if not then return the lower bound
    // otherwise return using dv
    Auction memory auction = auctions[accountId];
    int upperBound = auction.auction.upperBound;
    uint numSteps = block.timestamp / parameters.stepInterval; // will round down to whole number.

    // dv = (Vmax - Vmin) * numSteps
    return upperBound - int(auction.dv * numSteps);
  }

  //////////////
  // Helpers ///
  //////////////

  /**
   * @dev Compute the absolute value of `val`.
   *
   * @param val The number to absolute value.
   */
  function _abs(int val) internal pure returns (uint) {
    return uint(val < 0 ? -val : val);
  }
}
