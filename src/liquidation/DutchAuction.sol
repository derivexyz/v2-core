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
 * There are 3 types of auctions:
 *   1. SolventFastAuction:
 * start on account below maintenance margin, starting bid from 98% of Mtm to
 *          80% of Mtm, within 20 minutes
 * can be un-flagged if initial margin > 0
 *    2. SolventSlowAuction
 * continue if a solvent fast auction reach the 80% bound. Goes from 80% off MtM to 0.
 *          within 12 hours
 * can be un-flagged if initial margin > 0
 *    3. InsolventAuction
 * start insolvent auction that will be printing the liquidator cash or pay out from
 * security module to take out the position
 * the price of portfolio went from 0 to Initial margin (negative)
 * can be un-flagged if maintenance margin > 0
 */
contract DutchAuction is IDutchAuction, Ownable2Step {
  using SafeCast for int;
  using SafeCast for uint;
  using SignedDecimalMath for int;
  using DecimalMath for uint;

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
  SolventAuctionParams public solventAuctionParams;

  InsolventAuctionParams public insolventAuctionParams;

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
   * @dev This function is used to set the parameters for the fast and slow solvent auctions
   * @param _params New parameters
   */
  function setSolventAuctionParams(SolventAuctionParams memory _params) external onlyOwner {
    if (
      _params.startingMtMPercentage > 1e18 // cannot start with > 100% of mark to market
        || _params.liquidatorFeeRate > 0.1e18 // liquidator fee cannot be higher than 10%
    ) revert DA_InvalidParameter();

    solventAuctionParams = _params;
  }

  /**
   * @notice Sets the insolvent auction parameters
   * @dev This function is used to set the parameters for the dutch auction
   * @param _params New parameters
   */
  function setInsolventAuctionParams(InsolventAuctionParams memory _params) external onlyOwner {
    insolventAuctionParams = _params;
  }

  /**
   * @notice Called by the riskManager to start an auction
   * @dev Can only be auctioned by a risk manager and will start an auction
   * @param accountId The id of the account being liquidated
   * @param scenarioId id to compute the IM with for PMRM, ignored for basic manager
   */
  function startAuction(uint accountId, uint scenarioId) external {
    // todo: settle interest rate?

    if (_getMaintenanceMargin(accountId, scenarioId) >= 0) {
      revert DA_AccountIsAboveMaintenanceMargin();
    }

    if (auctions[accountId].ongoing) {
      revert DA_AuctionAlreadyStarted(accountId);
    }

    (int upperBound, int markToMarket) = _getVUpperAndMtM(accountId, scenarioId);
    if (upperBound > 0) {
      // solvent auction goes from upper bound -> 0

      // charge the account a fee to security module
      uint fee = _getLiquidationFee(accountId, scenarioId, markToMarket);
      //todo: charge fee

      _startSolventAuction(accountId, scenarioId, upperBound);
    } else {
      // insolvent auction start from 0 -> initial margin (negative number)
      int lowerBound = _getInitialMargin(accountId, scenarioId);
      _startInsolventAuction(accountId, scenarioId, lowerBound);
    }
  }

  /**
   * @notice Function used to begin insolvency logic for an auction that started as solvent
   * @dev This function can only be called on auctions that has already started as solvent
   * @param accountId the accountID being liquidated
   */
  function convertToInsolventAuction(uint accountId) external {
    // getCurrentBidPrice will revert if there is no auction for accountId going on
    if (_getCurrentBidPrice(accountId) > 0) {
      revert DA_AuctionNotEnteredInsolvency(accountId);
    }
    if (auctions[accountId].insolvent) {
      revert DA_AuctionAlreadyInInsolvencyMode(accountId);
    }

    uint scenarioId = auctions[accountId].scenarioId;

    // lower bound of insolvent auction is initial margin (negative)
    int lowerBound = _getInitialMargin(accountId, scenarioId);

    auctions[accountId].lastStepUpdate = block.timestamp;
    _startInsolventAuction(accountId, scenarioId, lowerBound);
  }

  /**
   * @notice a user submits a bid for a particular auction
   * @dev Takes in the auction and returns the account id
   * @param accountId Account ID of the liquidated account
   * @param bidderId Account ID of bidder, must be owned by msg.sender
   * @param percentOfAccount Percentage of account to liquidate, in 18 decimals
   * @return finalPercentage percentage of portfolio being liquidated
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
      int bidPrice = _getCurrentBidPrice(accountId);

      uint scenarioId = auctions[accountId].scenarioId;

      if (bidPrice == 0) revert DA_SolventAuctionEnded();

      // MtM is expected to be negative
      int markToMarket = _getMarkToMarket(accountId, scenarioId);

      // todo: get discount
      uint discount = 1e18;

      // calculate tha max proportion of the portfolio that can be liquidated
      uint pMax = _getMaxProportion(accountId, scenarioId, markToMarket, discount); // discount

      finalPercentage = percentOfAccount > pMax ? pMax : percentOfAccount;

      cashFromBidder = bidPrice.toUint256().multiplyDecimal(finalPercentage); // bid * f_max
    }

    // risk manager transfers portion of the account to the bidder
    // liquidator pays "cashFromLiquidator" to accountId
    riskManager.executeBid(accountId, bidderId, finalPercentage, cashFromBidder);

    emit Bid(accountId, bidderId, finalPercentage, cashFromBidder);

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
    if (!auctions[accountId].ongoing) revert DA_NotOngoingAuction();

    if (auctions[accountId].insolvent) {
      int mm = _getMaintenanceMargin(accountId, auctions[accountId].scenarioId);
      return mm > 0;
    } else {
      int im = _getInitialMargin(accountId, auctions[accountId].scenarioId);
      return im > 0;
    }
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
    return -10e18;
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
    if (block.timestamp < lastIncrement + insolventAuctionParams.coolDown && lastIncrement != 0) {
      revert DA_CannotStepBeforeCoolDownEnds(block.timestamp, lastIncrement + insolventAuctionParams.coolDown);
    }

    uint newStep = ++auction.stepInsolvent;
    if (newStep > insolventAuctionParams.totalSteps) revert DA_MaxStepReachedInsolventAuction();

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
  function getMaxProportion(uint accountId, uint scenarioId) external view returns (uint) {
    int markToMarket = _getMarkToMarket(accountId, scenarioId);

    uint discount = 0; //getDiscount;

    return _getMaxProportion(accountId, auctions[accountId].scenarioId, markToMarket, discount);
  }

  /**
   * @dev get the fee that should be transferred to the security module
   */
  function _getLiquidationFee(uint accountId, uint scenarioId, int markToMarket) internal view returns (uint fee) {
    uint maxProportion = _getMaxProportion(accountId, scenarioId, markToMarket, 1e18);

    fee =
      maxProportion.multiplyDecimal(IntLib.abs(markToMarket)).multiplyDecimal(solventAuctionParams.liquidatorFeeRate);
  }

  /**
   * @notice gets the upper bound for the liquidation price. This should be a static discount of market to market
   */
  function getVUpperAndMtM(uint accountId, uint scenarioId) external view returns (int, int) {
    return _getVUpperAndMtM(accountId, scenarioId);
  }

  /**
   * @notice gets the current bid price for a particular auction at the current block
   * @dev returns the current bid price for a particular auction
   * @param accountId Id of account being liquidated
   * @return int the current bid price for the auction
   */
  function getCurrentBidPrice(uint accountId) external view returns (int) {
    return _getCurrentBidPrice(accountId);
  }

  ///////////////
  // internal //
  ///////////////

  /**
   * @notice Gets the maximum size of the portfolio that could be bought at the current price
   * @dev assuming negative IM and MtM, the formula for max portion is:
   *
   *                        IM
   *    f = ----------------------------------
   *         IM - MtM * discount_percentage
   *
   *
   * @param accountId the id of the account being liquidated
   * @param discountPercentage the discount percentage of MtM the auction is offering at (dropping from 98% to 0%)
   * @return uint the proportion of the portfolio that could be bought at the current price
   */
  function _getMaxProportion(uint accountId, uint scenarioId, int markToMarket, uint discountPercentage)
    internal
    view
    returns (uint)
  {
    // IM is expected to be negative
    int initialMargin = _getInitialMargin(accountId, scenarioId);

    int denominator = initialMargin - markToMarket * int(discountPercentage);

    return initialMargin.divideDecimal(denominator).toUint256();
  }

  /**
   * @notice Starts an auction that starts with a positive upper bound
   * @dev Function is here to break up the logic for insolvent and solvent auctions
   * @param upperBound The upper bound of the auction that must be greater than zero
   * @param accountId The id of the account being liquidated
   */
  function _startSolventAuction(uint accountId, uint scenarioId, int upperBound) internal {
    // this function will revert if upper bound is somehow negative

    auctions[accountId] = Auction({
      accountId: accountId,
      scenarioId: scenarioId,
      insolvent: false,
      ongoing: true,
      startTime: block.timestamp,
      dv: 0, // ?? todo
      stepInsolvent: 0,
      lastStepUpdate: 0,
      upperBound: upperBound
    });

    emit AuctionStarted(accountId, upperBound, 0, block.timestamp, false);
  }

  /**
   * @notice Explain to an end user what this does
   * @dev Explain to a developer any extra details
   * @param lowerBound The lowerBound, the minimum acceptable bid for an insolvency
   * @param accountId the id of the account that is being liquidated
   */
  function _startInsolventAuction(uint accountId, uint scenarioId, int lowerBound) internal {
    // decrease value every step
    uint dv = IntLib.abs(lowerBound) / insolventAuctionParams.totalSteps;

    auctions[accountId] = Auction({
      accountId: accountId,
      scenarioId: scenarioId,
      insolvent: true,
      ongoing: true,
      startTime: block.timestamp,
      dv: dv,
      stepInsolvent: 0,
      lastStepUpdate: 0,
      upperBound: 0
    });
    emit AuctionStarted(accountId, 0, lowerBound, block.timestamp, true);
  }

  function _getDiscountPercentage(uint startTimestamp, uint currentTimestamp) internal view returns (uint) {
    // todo: impl
    return 0.8e18;
  }

  /**
   * @dev get the upper bound of a solvent auction, which is the mark to market value of a portfolio
   */
  function _getVUpperAndMtM(uint accountId, uint scenarioId) internal view returns (int vUpper, int markToMarket) {
    address manager = address(accounts.manager(accountId));
    markToMarket = _getMarkToMarket(accountId, scenarioId);
    vUpper = markToMarket.multiplyDecimal(int64(solventAuctionParams.startingMtMPercentage));
  }

  /**
   * @notice get the mark to market of an account from the account's manager.
   * @dev scenarioId will be ignored for basic manager
   */
  function _getMarkToMarket(uint accountId, uint scenarioId) internal view returns (int markToMarket) {
    address manager = address(accounts.manager(accountId));
    markToMarket = ILiquidatableManager(manager).getMarkToMarket(accountId, scenarioId);
  }

  /**
   * @notice get the initial margin of an account from the account's manager.
   * @dev scenarioId will be ignored for basic manager
   */
  function _getInitialMargin(uint accountId, uint scenarioId) internal view returns (int vLower) {
    address manager = address(accounts.manager(accountId));

    vLower = ILiquidatableManager(manager).getMarginWithData(accountId, true, scenarioId);
  }

  /**
   * @notice get the maintenance margin of an account from the account's manager
   * @dev scenarioId will be ignored for basic manager
   */
  function _getMaintenanceMargin(uint accountId, uint scenarioId) internal view returns (int vLower) {
    address manager = address(accounts.manager(accountId));

    vLower = ILiquidatableManager(manager).getMarginWithData(accountId, false, scenarioId);
  }

  /**
   * @notice gets the current bid price for a particular auction at the current block
   * @dev returns the current bid price for a particular auction
   * @param accountId the uint id related to the auction
   * @return int the current bid price for the auction
   */
  function _getCurrentBidPrice(uint accountId) internal view returns (int) {
    Auction memory auction = auctions[accountId];

    if (!auction.ongoing) revert DA_AuctionNotStarted(accountId);

    if (auction.insolvent) {
      // @invariant: if insolvent, bids should always be negative
      uint numSteps = auction.stepInsolvent;
      return 0 - (auction.dv * numSteps).toInt256();
    } else {
      // @invariant: if solvent, bids should always be positive
      uint totalLength = solventAuctionParams.fastAuctionLength + solventAuctionParams.slowAuctionLength;
      if (block.timestamp > auction.startTime + totalLength) {
        return 0;
      }

      // calculate discount percentage
      uint discount = _getDiscountPercentage(auction.startTime, block.timestamp); //getDiscount;

      int bidPrice = auction.upperBound.multiplyDecimal(int(discount));
      return bidPrice;
    }
  }
}
