// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// interfaces
import "../interfaces/IPCRM.sol";
import "../interfaces/IDutchAuction.sol";
import "../Accounts.sol";

// inherited
import "synthetix/Owned.sol";
import "openzeppelin/utils/math/SafeMath.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/math/SignedMath.sol";
import "synthetix/DecimalMath.sol";
import "../libraries/IntLib.sol";

// TODO: remove forge test before merging
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
  using SafeCast for int;
  using SafeCast for uint;
  using DecimalMath for uint;

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
    /// The current step if the auction is insolvent
    uint stepInsolvent;
  }

  struct DutchAuctionParameters {
    /// Big number, Length of each step in seconds
    uint stepInterval;
    /// Big number: Total length of an auction in seconds
    uint lengthOfAuction;
    /// Big number: The address of the security module
    address securityModule;
    // Big Number: spot shock
    uint spotShock;
  }

  /// @dev AccountId => Auction for when an auction is started
  mapping(uint => Auction) public auctions;

  /// @dev The risk manager that is the parent of the dutch auction contract
  IPCRM public immutable riskManager;

  /// @dev The accounts contract for resolving address to accountIds
  Accounts public immutable accounts;

  /// @dev The parameters for the dutch auction
  DutchAuctionParameters private parameters;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(address _riskManager, address _accounts) Owned() {
    riskManager = IPCRM(_riskManager);
    accounts = Accounts(_accounts);
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
    (int upperBound, int lowerBound) = _getBounds(accountId, spot);
    // covers the case where an auction could start as insolvent, upperbound < 0
    if (upperBound > 0) {
      _startSolventAuction(upperBound, accountId);
    } else {
      _startInsolventAuction(lowerBound, accountId);
    }

    emit AuctionStarted(accountId, upperBound, lowerBound, block.timestamp, auctions[accountId].insolvent);
  }

  /**
   * @notice Function used to begin insolvency logic for an auction that started as solvent
   * @dev Takes in the auction and returns the account id
   * @param accountId the bytesId that corresponds to the auction being marked as liquidatable
   * @return bool The state of the marked insolvent auction, should be true or should revert
   */
  function markAsInsolventLiquidation(uint accountId) external returns (bool) {
    if (address(riskManager) != msg.sender) {
      revert DA_NotRiskManager();
    }

    if (_getCurrentBidPrice(accountId) > 0) {
      revert DA_AuctionNotEnteredInsolvency(accountId);
    }

    uint spot = riskManager.getSpot();
    (, int lowerBound) = _getBounds(accountId, spot);
    _startInsolventAuction(lowerBound, accountId);

    return auctions[accountId].insolvent;
  }

  /**
   * @notice a user submits a bid for a particular auction
   * @dev Takes in the auction and returns the account id
   * @param accountId the bytesId that corresponds to a particular auction
   * @return amount the amount as a percentage of the portfolio that the user is willing to purchase
   */
  function bid(uint accountId, uint bidderId, uint amount) external returns (uint) {
    if (amount > DecimalMath.UNIT) {
      revert DA_AmountTooLarge(accountId, amount);
    } else if (amount == 0) {
      revert DA_AmountInvalid(accountId, amount);
    }

    if (auctions[accountId].ongoing == false) {
      revert DA_AuctionNotOngoing(accountId);
    }

    // need to check if the timelimit for the auction has been ecplised
    if (block.timestamp > auctions[accountId].endTime) {
      revert DA_AuctionEnded(accountId);
    }

    // get bidder address and make sure that they own the account
    if (accounts.ownerOf(bidderId) != msg.sender) {
      revert DA_BidderNotOwner(bidderId, msg.sender);
    }

    // get compares max and the f_max amount
    uint f_max = _getMaxProportion(accountId);
    amount = amount > f_max ? f_max : amount;

    if (auctions[accountId].insolvent) {
      // TODO: Anton
      // This case someone is getting payed to take on the risk
    } else {
      // this case someone is paying to take on the risk
      uint cashAmount = _getCurrentBidPrice(accountId).toUint256().multiplyDecimal(amount); // bid * f_max
      riskManager.executeBid(accountId, bidderId, amount, cashAmount);
      // need to check if the bounds are calculated after a bid
      // (int upperBound, int lowerBound) = _getBounds(accountId, riskManager.getSpot());
      // auction.auction.upperBound = upperBound;
    }

    emit Bid(accountId, bidderId, block.timestamp);

    // terminating the auction if the initial margin is positive
    // This has to be checked after the scailing
    if (riskManager.getInitialMargin(accountId) >= 0) {
      _terminateAuction(accountId);
    }

    return amount;
  }

  /**
   * @notice Internal function to terminate an auction
   * @dev Changes the value of an auction and flags that it can no longer be bid on
   * @param accountId The accountId of account that is being liquidated
   */
  function _terminateAuction(uint accountId) internal {
    Auction storage auction = auctions[accountId];
    auction.ongoing = false;
    auction.endTime = block.timestamp;
    emit AuctionEnded(accountId, block.timestamp);
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
   * @notice This function can only be used for when the auction is insolvent
   * @dev This is to prevent an auction falling all the way through if a provider or the network goes down
   * @param accountId the accountId that relates to the auction that is being stepped
   * @return uint the step that the auction is on
   */
  function incrementInsolventAuction(uint accountId) external returns (uint) {
    Auction storage auction = auctions[accountId];
    if (!auction.insolvent) {
      revert DA_AuctionNotInsolventCannotStep(accountId);
    }

    auction.stepInsolvent++;

    return auction.stepInsolvent;
  }

  /**
   * @notice External view to get the maximum size of the portfolio that could be bought at the current price
   * @param accountId the id of the account being liquidated
   * @return uint the proportion of the portfolio that could be bought at the current price
   */
  function getMaxProportion(uint accountId) external returns (uint) {
    return _getMaxProportion(accountId);
  }

  /**
   * @notice gets the upper bound for the liquidation price
   * @dev requires the accountId and the spot price to mark each asset at a particular value
   * @param accountId the accountId of the account that is being liquidated
   * @param spot the spot price of the asset,
   */
  function getBounds(uint accountId, uint spot) external view returns (int, int) {
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

  /**
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
   * @notice Gets the maximum size of the portfolio that could be bought at the current price
   * @param accountId the id of the account being liquidated
   * @return uint the proportion of the portfolio that could be bought at the current price
   */
  function _getMaxProportion(uint accountId) internal returns (uint) {
    int initialMargin = riskManager.getInitialMargin(accountId);
    int currentBidPrice = _getCurrentBidPrice(accountId);

    if (currentBidPrice <= 0) {
      return DecimalMath.UNIT;
    }

    // IM is always negative under the margining system.
    int fMax = (initialMargin * 1e18) / (initialMargin - currentBidPrice); // needs to return big number, how to do this with ints.
    if (fMax > 1e18) {
      return DecimalMath.UNIT;
    } else {
      return fMax.toUint256();
    }
  }

  /**
   * @notice Starts an auction that starts with a positive upper bound
   * @dev Function is here to break up the logic for insolvent and solvent auctions
   * @param upperBound The upper bound of the auction that must be greater than zero
   * @param accountId The id of the account being liquidated
   */
  function _startSolventAuction(int upperBound, uint accountId) internal {
    uint dv = IntLib.abs(upperBound).divideDecimal(parameters.lengthOfAuction); // as the auction starts in the positive, recalculate when insolvency occurs

    auctions[accountId] = Auction({
      insolvent: false,
      ongoing: true,
      startTime: block.timestamp,
      endTime: block.timestamp + parameters.lengthOfAuction, // half the auction length as 50% of the auction should be spent on each side
      dv: dv,
      stepInsolvent: 1,
      auction: AuctionDetails({accountId: accountId, upperBound: upperBound, lowerBound: 0})
    });
  }

  /**
   * @notice Explain to an end user what this does
   * @dev Explain to a developer any extra details
   * @param lowerBound The lowerBound, the minimum acceptable bid for an insolvency
   * @param accountId the id of the account that is being liquidated
   */
  function _startInsolventAuction(int lowerBound, uint accountId) internal {
    uint dv = IntLib.abs(lowerBound).divideDecimal(parameters.lengthOfAuction);
    // as the auction starts in the negative, recalculate when insolvency occurs

    auctions[accountId] = Auction({
      insolvent: true,
      ongoing: true,
      startTime: block.timestamp,
      endTime: block.timestamp + parameters.lengthOfAuction, // half the length of the auction as 50% of the auction should be spent on each side
      dv: dv,
      stepInsolvent: 1,
      auction: AuctionDetails({accountId: accountId, upperBound: 0, lowerBound: lowerBound})
    });
    emit Insolvent(accountId);
  }

  /**
   * @notice gets the upper bound for the liquidation price
   * @dev requires the accountId and the spot price to mark each asset at a particular value
   * @param accountId the accountId of the account that is being liquidated
   * @param spot the spot price of the asset,
   */
  function _getBounds(uint accountId, uint spot) internal view returns (int maximum, int minimum) {
    IPCRM.ExpiryHolding[] memory expiryHoldings = riskManager.getGroupedHoldings(accountId);
    int cash = riskManager.getCashAmount(accountId);
    maximum = cash;
    minimum = cash;

    for (uint i = 0; i < expiryHoldings.length; i++) {
      // iterate over all strike holdings, if they are Long calls mark them to spot, if they are long puts consider them at there strike, shorts to 0
      (int max, int min) = _markStrike(expiryHoldings[i].strikes, spot);
      maximum += max;
      minimum += min;
    }
  }

  /**
   * @notice calculates the maximum and minimum aggregated value of all strike at a particular price
   * @param strikes the strikes that are being marked
   * @param spot the spot price of the asset
   * @dev returns the minimum and maximum aggregated value of all strike at a particular price
   */
  function _markStrike(IPCRM.StrikeHolding[] memory strikes, uint spot) internal view returns (int max, int min) {
    for (uint j = 0; j < strikes.length; j++) {
      // calls
      {
        int numCalls = strikes[j].calls;
        max += SignedMath.max(numCalls, 0) * spot.multiplyDecimal(parameters.spotShock).toInt256();
        min += SignedMath.min(numCalls, 0) * spot.multiplyDecimal(parameters.spotShock).toInt256();
        // puts
        int numPuts = strikes[j].puts;
        max += SignedMath.max(numPuts, 0) * int64(strikes[j].strike);
        min += SignedMath.min(numPuts, 0) * int64(strikes[j].strike);
      }
    }
  }

  /**
   * @notice gets the current bid price for a particular auction at the current block
   * @dev returns the current bid price for a particular auction
   * @param accountId the uint id related to the auction
   * @return int the current bid price for the auction
   */
  function _getCurrentBidPrice(uint accountId) internal view returns (int) {
    Auction memory auction = auctions[accountId];
    int upperBound = auction.auction.upperBound;
    uint numSteps;
    if (auction.insolvent) {
      numSteps = auction.stepInsolvent;
      return 0 - auction.dv.multiplyDecimal(auction.stepInsolvent).toInt256();
    } else {
      int bid = upperBound
        - auction.dv.multiplyDecimal((block.timestamp - auction.startTime).divideDecimal(parameters.stepInterval))
          .toInt256();
      // have to call markAsInsolvent before bid can be negative
      if (bid <= 0) {
        return 0;
      } else {
        return bid;
      }
    }
  }
}
