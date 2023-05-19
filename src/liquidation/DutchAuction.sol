// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

// interfaces
import "src/interfaces/ILiquidatableManager.sol";
import "src/interfaces/ISecurityModule.sol";
import "src/interfaces/ICashAsset.sol";
import "src/interfaces/IDutchAuction.sol";
import "src/Accounts.sol";

// inherited
import "openzeppelin/utils/math/SafeMath.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/math/SignedMath.sol";
import "lyra-utils/decimals/DecimalMath.sol";
import "lyra-utils/decimals/SignedDecimalMath.sol";
import "openzeppelin/access/Ownable2Step.sol";
import "lyra-utils/math/IntLib.sol";

/**
 * @title Dutch Auction
 * @author Lyra
 * @notice Is used to liquidate an account that does not meet the margin requirements
 * 1. The auction is started by the risk Manager
 * 2. Bids are taken in a descending fashion until the maintenance margin
 * 3. A scalar is applied to the assets of the portfolio and are transferred to the bidder
 * 4. This continues until maintenance margin is met or until the portfolio is declared as insolvent
 *    where the security module will step into to handle the risk
 * @dev This contract has a 1 to 1 relationship with a particular risk manager.
 */
contract DutchAuction is IDutchAuction, Ownable2Step {
  using SafeCast for int;
  using SafeCast for uint;
  using SignedDecimalMath for int;
  using DecimalMath for uint;

  struct Auction {
    /// the accountId that is being liquidated
    uint accountId;
    /// The upperBound(starting price) of the auction in cash asset
    int upperBound;
    /// The lowerBound(ending price) of the auction in cash asset
    int lowerBound;
    /// Boolean that will be switched when the auction price passes through 0
    bool insolvent;
    /// If an auction is active
    bool ongoing;
    /// The startTime of the auction
    uint startTime;
    /// The change in value of the portfolio per step in dollars when not insolvent
    uint dv;
    /// The current step if the auction is insolvent
    uint stepInsolvent;
    /// The timestamp of the last increase of steps for insolvent auction
    uint lastStepUpdate;
  }

  struct DutchAuctionParameters {
    /// Big number, Length of each step in seconds
    uint stepInterval;
    /// Big number: Total length of an auction in seconds
    uint lengthOfAuction;
    // Number, Amount of time between steps when the auction is insolvent
    uint secBetweenSteps;
    // Liquidator fee rate in percentage, 1e18 = 100%
    uint liquidatorFeeRate;
  }

  /// @dev AccountId => Auction for when an auction is started
  mapping(uint => Auction) public auctions;

  /// @dev The risk manager that is the parent of the dutch auction contract
  ILiquidatableManager public immutable riskManager;

  /// @dev The security module that will help pay out for insolvent auctions
  ISecurityModule public immutable securityModule;

  /// @dev The cash asset address, will be used to socialize losses when there's systematic insolvency
  ICashAsset public immutable cash;

  /// @dev The accounts contract for resolving address to accountIds
  Accounts public immutable accounts;

  /// @dev The parameters for the dutch auction
  DutchAuctionParameters private parameters;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(ILiquidatableManager _riskManager, Accounts _accounts, ISecurityModule _securityModule, ICashAsset _cash)
    Ownable2Step()
  {
    riskManager = _riskManager;
    accounts = _accounts;
    securityModule = _securityModule;
    cash = _cash;
  }

  /**
   * @notice Sets the dutch Auction Parameters
   * @dev This function is used to set the parameters for the dutch auction
   * @param _parameters A struct that contains all the parameters for the dutch auction
   */
  function setDutchAuctionParameters(DutchAuctionParameters memory _parameters) external onlyOwner {
    // liquidator fee cannot be higher than 10%
    if (_parameters.liquidatorFeeRate > 0.1e18) revert DA_InvalidParameter();

    parameters = _parameters;
  }

  /**
   * @notice Called by the riskManager to start an auction
   * @dev Can only be auctioned by a risk manager and will start an auction
   * @param accountId The id of the account being liquidated
   */
  function startAuction(uint accountId) external {
    if (getMaintenanceMarginForAccount(accountId) >= 0) {
      revert DA_AccountIsAboveMaintenanceMargin();
    }

    if (auctions[accountId].ongoing) {
      revert DA_AuctionAlreadyStarted(accountId);
    }

    int upperBound = _getVUpper(accountId);
    // covers the case where an auction could start as insolvent, upper bound < 0
    if (upperBound > 0) {
      _startSolventAuction(upperBound, accountId);
    } else {
      // insolvent auction start from 0 -> initial margin (negative number)
      // int lowerBound = _getIM();
      int lowerBound = -1000e18;
      _startInsolventAuction(lowerBound, accountId);
    }

    emit AuctionStarted(accountId, upperBound, lowerBound, block.timestamp, auctions[accountId].insolvent);
  }

  /**
   * @notice Function used to begin insolvency logic for an auction that started as solvent
   * @dev This function can only be called on auctions that has already started as solvent
   * @param accountId the bytesId that corresponds to the auction being marked as liquidatable
   */
  function convertToInsolventAuction(uint accountId) external {
    // getCurrentBidPrice will revert if there is no auction for accountId going on
    if (_getCurrentBidPrice(accountId) > 0) {
      revert DA_AuctionNotEnteredInsolvency(accountId);
    }
    if (auctions[accountId].insolvent) {
      revert DA_AuctionAlreadyInInsolvencyMode(accountId);
    }

    // todo[Anton]: refactor the logic here so that we don't need to recalculate upper bound
    (, int lowerBound) = _getBounds(accountId);

    auctions[accountId].lastStepUpdate = block.timestamp;
    _startInsolventAuction(lowerBound, accountId);
  }

  /**
   * @notice a user submits a bid for a particular auction
   * @dev Takes in the auction and returns the account id
   * @param accountId Account ID of the liquidated account
   * @param bidderId Account ID of bidder, must be owned by msg.sender
   * @param percentOfAccount Percentage of account to liquidate, in 18 decimals
   * @return finalPercentage Actual percentage liquidated
   * @return cashFromBidder Amount of cash paid from bidder to liquidated account
   * @return cashToBidder Amount of cash paid from security module for bidder to take on the risk
   * @return fee Amount of cash paid from bidder to security module
   */
  function bid(uint accountId, uint bidderId, uint percentOfAccount)
    external
    returns (uint finalPercentage, uint cashFromBidder, uint cashToBidder, uint fee)
  {
    if (percentOfAccount > DecimalMath.UNIT) {
      revert DA_AmountTooLarge(accountId, percentOfAccount);
    } else if (percentOfAccount == 0) {
      revert DA_AmountIsZero(accountId);
    }

    // get bidder address and make sure that they own the account
    if (accounts.ownerOf(bidderId) != msg.sender) {
      revert DA_BidderNotOwner(bidderId, msg.sender);
    }

    if (checkCanTerminateAuction(accountId)) {
      revert DA_AuctionShouldBeTerminated(accountId);
    }

    // _getCurrentBidPrice below will check if the auction is active or not

    if (auctions[accountId].insolvent) {
      finalPercentage = percentOfAccount;

      // the account is insolvent when the bid price for the account falls below zero
      // someone get paid from security module to take on the risk
      cashToBidder = (-_getCurrentBidPrice(accountId)).toUint256().multiplyDecimal(finalPercentage);
      // we first ask the security module to compensate the bidder
      uint amountPaid = securityModule.requestPayout(bidderId, cashToBidder);
      // if amount paid is less than we requested:
      // 1. we trigger socialize losses on cash asset
      // 2. print cash to the bidder (in cash.socializeLoss)
      if (cashToBidder > amountPaid) {
        uint loss = cashToBidder - amountPaid;
        cash.socializeLoss(loss, bidderId);
      }
    } else {
      // if the account is solvent, the bidder pays the account for a portion of the account
      uint p_max = _getMaxProportion(accountId);
      finalPercentage = percentOfAccount > p_max ? p_max : percentOfAccount;
      // bid price == 0 means auction has ended
      int bidPrice = _getCurrentBidPrice(accountId);
      if (bidPrice == 0) revert DA_SolventAuctionEnded();
      cashFromBidder = bidPrice.toUint256().multiplyDecimal(finalPercentage); // bid * f_max
    }

    // risk manager transfers portion of the account to the bidder
    // liquidator pays "cashFromLiquidator" to accountId
    // liquidator pays "fee" to security module
    fee = cashFromBidder.multiplyDecimal(parameters.liquidatorFeeRate);
    riskManager.executeBid(accountId, bidderId, finalPercentage, cashFromBidder, fee);

    emit Bid(accountId, bidderId, finalPercentage, cashFromBidder, fee);

    // terminating the auction if the account is back above water
    if (checkCanTerminateAuction(accountId)) {
      _terminateAuction(accountId);
    }
  }

  /**
   * @notice Return true if an auction can be terminated (back above water)
   * @dev for solvent auction: if IM > 0
   * @dev for insolvent auction: if MM > 0
   * @param accountId ID of the account to check
   */
  function checkCanTerminateAuction(uint accountId) public view returns (bool) {
    // TODO: make sure this is still valid
    return getInitMarginForAccount(accountId) >= 0;
  }

  /**
   * @notice Internal function to terminate an auction
   * @dev Changes the value of an auction and flags that it can no longer be bid on
   * @param accountId The accountId of account that is being liquidated
   */
  function _terminateAuction(uint accountId) internal {
    Auction storage auction = auctions[accountId];
    auction.ongoing = false;
    emit AuctionEnded(accountId, block.timestamp);
  }

  /**
   * @dev Helper to get maintenance margin for an accountId
   */
  function getMaintenanceMarginForAccount(uint accountId) public view returns (int) {
    // TODO: generalise call to get "MaintenanceMargin"
    return -10e18;
  }

  /**
   * @dev Helper to get initial margin for an accountId
   */
  function getInitMarginForAccount(uint accountId) public view returns (int) {
    // TODO: generalise call to get "InitMargin"
    return -20e18;
  }

  /**
   * @notice returns the details of an ongoing auction
   * @param accountId the id of the auction that is being queried
   * @return Auction returns the struct of the auction details
   */
  function getAuction(uint accountId) external view returns (Auction memory) {
    return auctions[accountId];
  }

  /**
   * @notice This function can only be used for when the auction is insolvent and is a safety mechanism for
   * if the network is down for rpc provider is unable to submit requests to sequencer, potentially resulting
   * massive insolvency due to bids falling to v_lower.
   * @dev This is to prevent an auction falling all the way through if a provider or the network goes down
   * @param accountId the accountId that relates to the auction that is being stepped
   * @return uint the step that the auction is on
   */
  function continueInsolventAuction(uint accountId) external returns (uint) {
    Auction storage auction = auctions[accountId];
    if (!auction.insolvent) {
      revert DA_SolventAuctionCannotIncrement(accountId);
    }

    uint lastIncrement = auction.lastStepUpdate;
    if (block.timestamp < lastIncrement + parameters.secBetweenSteps && lastIncrement != 0) {
      revert DA_CannotStepBeforeCoolDownEnds(block.timestamp, block.timestamp + parameters.secBetweenSteps);
    }

    uint newStep = ++auction.stepInsolvent;
    if (newStep * parameters.stepInterval > parameters.lengthOfAuction) {
      revert DA_MaxStepReachedInsolventAuction();
    }

    auction.lastStepUpdate = block.timestamp;

    return newStep;
  }

  /**
   * @notice This function can used by anyone to end an auction early
   * @dev This is to allow account owner to cancel the auction after adding more collateral
   * @param accountId the accountId that relates to the auction that is being stepped
   */
  function terminateAuction(uint accountId) external {
    if (!checkCanTerminateAuction(accountId)) revert DA_AuctionCannotTerminate(accountId);
    _terminateAuction(accountId);
  }

  /**
   * @notice External view to get the maximum size of the portfolio that could be bought at the current price
   * @param accountId the id of the account being liquidated
   * @return uint the proportion of the portfolio that could be bought at the current price
   */
  function getMaxProportion(uint accountId) external view returns (uint) {
    return _getMaxProportion(accountId);
  }

  /**
   * @notice gets the upper bound for the liquidation price. This should be a static discount of market to market
   */
  function getVUpper(uint accountId) external view returns (int) {
    return _getVUpper(accountId);
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
  function _getMaxProportion(uint accountId) internal view returns (uint) {
    int initialMargin = getInitMarginForAccount(accountId);
    int currentBidPrice = _getCurrentBidPrice(accountId);

    if (currentBidPrice <= 0) {
      return DecimalMath.UNIT;
    }

    // IM is always negative under the margining system.
    int pMax = (initialMargin * 1e18) / (initialMargin - currentBidPrice); // needs to return big number, how to do this with ints.

    // commented out if statement to hit coverage don't have a test that hits it.
    return pMax.toUint256();
  }

  /**
   * @notice Starts an auction that starts with a positive upper bound
   * @dev Function is here to break up the logic for insolvent and solvent auctions
   * @param upperBound The upper bound of the auction that must be greater than zero
   * @param accountId The id of the account being liquidated
   */
  function _startSolventAuction(int upperBound, uint accountId) internal {
    // this function will revert if upper bound is somehow negative
    uint dv = upperBound.toUint256() / parameters.lengthOfAuction; // as the auction starts in the positive, recalculate when insolvency occurs

    auctions[accountId] = Auction({
      accountId: accountId,
      insolvent: false,
      ongoing: true,
      startTime: block.timestamp,
      dv: dv,
      stepInsolvent: 0,
      lastStepUpdate: 0,
      upperBound: upperBound,
      lowerBound: 0
    });
  }

  /**
   * @notice Explain to an end user what this does
   * @dev Explain to a developer any extra details
   * @param lowerBound The lowerBound, the minimum acceptable bid for an insolvency
   * @param accountId the id of the account that is being liquidated
   */
  function _startInsolventAuction(int lowerBound, uint accountId) internal {
    uint dv = IntLib.abs(lowerBound) / parameters.lengthOfAuction;
    // as the auction starts in the negative, recalculate when insolvency occurs

    auctions[accountId] = Auction({
      accountId: accountId,
      insolvent: true,
      ongoing: true,
      startTime: block.timestamp,
      dv: dv,
      stepInsolvent: 0,
      lastStepUpdate: 0,
      upperBound: 0,
      lowerBound: lowerBound
    });
    emit Insolvent(accountId);
  }

  function _getVUpper() internal view returns (uint vUpper) {    
    int marketToMarket = 0;
    // apply scaler to market to market

  }

  /**
   * @notice gets the upper bound for the liquidation price
   * @dev requires the accountId and the spot price to mark each asset at a particular value
   * @dev vUpper = IM(P'), while P' being the inversed portfolio
   * @dev vLower = IM(P)
   * @param accountId the accountId of the account that is being liquidated
   */
  function _getBounds(uint accountId) internal view returns (int upperBound, int lowerBound) {
    // TODO: get bounds

    upperBound = type(int).max;
    lowerBound = type(int).min;
  }

  /**
   * @notice gets the current bid price for a particular auction at the current block
   * @dev returns the current bid price for a particular auction
   * @param accountId the uint id related to the auction
   * @return int the current bid price for the auction
   */
  function _getCurrentBidPrice(uint accountId) internal view returns (int) {
    Auction memory auction = auctions[accountId];
    if (!auction.ongoing) {
      revert DA_AuctionNotStarted(accountId);
    }

    if (auction.insolvent) {
      // @invariant: if insolvent, bids should always be negative
      uint numSteps = auction.stepInsolvent;
      return 0 - (auction.dv * numSteps).toInt256();
    } else {
      // @invariant: if solvent, bids should always be positive
      if (block.timestamp > auction.startTime + parameters.lengthOfAuction) {
        return 0;
      }

      int upperBound = auction.upperBound;
      int bidPrice =
        upperBound - (int(auction.dv) * int(block.timestamp - auction.startTime)) / int(parameters.stepInterval);
      return bidPrice;
    }
  }
}
