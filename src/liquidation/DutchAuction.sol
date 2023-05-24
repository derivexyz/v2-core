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

import "forge-std/console2.sol";

/**
 * @title Dutch Auction
 * @author Lyra
 * @notice Is used to liquidate an account that does not meet the margin requirements
 * There are 3 stages of an auction on an account:
 *
 * 1. SolventFastAuction:
 * start if account below maintenance margin, starting bid from 98% of Mtm to
 * 80% of Mtm, within a short period of time (e.g 20 minutes)
 * can be un-flagged if buffer margin > 0
 *
 * 2. SolventSlowAuction
 * continue if a solvent fast auction reach the 80% bound. Goes from 80% off MtM to 0.
 * within a longer period of time (e.g. 12 hours)
 * can be un-flagged if buffer margin > 0
 *
 * 3. InsolventAuction
 * insolvent auction will kick off if no one bid on the solvent auction, meaning no one wants to take the portfolio even if it's given for free.
 * or, it can be started if mark to market value of a portfolio is negative.
 * the insolvent auction that will print the liquidator cash or pay out from security module for liquidator to take the position
 * the price of portfolio went from 0 to Buffer margin * scaler (negative)
 * can be un-flagged if maintenance margin > 0
 */
contract DutchAuction is IDutchAuction, Ownable2Step {
  using SafeCast for int;
  using SafeCast for uint;
  using SignedDecimalMath for int;
  using DecimalMath for uint;

  /// @dev Help defines buffer margin: maintenance margin - bufferPercentage * (maintenance margin - mtm)
  int public bufferMarginPercentage;

  /// @dev AccountId => Auction for when an auction is started
  mapping(uint => Auction) public auctions;

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

  constructor(Accounts _accounts, ISecurityModule _securityModule, ICashAsset _cash) Ownable2Step() {
    accounts = _accounts;
    securityModule = _securityModule;
    cash = _cash;
  }

  /**
   * @notice Set buffer margin that will be used to determine the target margin level we liquidate to
   * @dev if set to 0, we liquidate to maintenance margin. If set to 0.3, approximately to initial margin
   */
  function setBufferMarginPercentage(int _bufferMarginPercentage) external onlyOwner {
    if (_bufferMarginPercentage > 0.3e18) revert DA_InvalidBufferMarginParameter();
    bufferMarginPercentage = _bufferMarginPercentage;
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
        || _params.fastAuctionCutoffPercentage > _params.startingMtMPercentage
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
   * @dev anyone can start an auction for an account
   * @param accountId The id of the account being liquidated
   * @param scenarioId id to compute the IM with for PMRM, ignored for basic manager
   */
  function startAuction(uint accountId, uint scenarioId) external {
    // settle pending interest rate on an account
    address manager = address(accounts.manager(accountId));
    ILiquidatableManager(manager).settleInterest(accountId);

    (int maintenanceMargin, int bufferMargin, int markToMarket) = _getMarginAndMarkToMarket(accountId, scenarioId);

    // can only start auction if maintenance margin > 0
    if (maintenanceMargin >= 0) revert DA_AccountIsAboveMaintenanceMargin();

    if (auctions[accountId].ongoing) revert DA_AuctionAlreadyStarted();

    if (markToMarket > 0) {
      // charge the account a fee to security module
      uint fee = _getLiquidationFee(markToMarket, bufferMargin);
      //todo: charge fee

      // solvent auction goes from mark to market * static discount -> 0
      _startSolventAuction(accountId, scenarioId, markToMarket, fee);
    } else {
      // insolvent auction start from 0 -> buffer margin (negative number) * scaler
      int lowerBound = bufferMargin.multiplyDecimal(insolventAuctionParams.bufferMarginScaler);
      _startInsolventAuction(accountId, scenarioId, lowerBound);
    }
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
   */
  function bid(uint accountId, uint bidderId, uint percentOfAccount)
    external
    returns (uint finalPercentage, uint cashFromBidder, uint cashToBidder)
  {
    if (percentOfAccount > DecimalMath.UNIT || percentOfAccount == 0) {
      revert DA_InvalidPercentage();
    }

    // get bidder address and make sure that they own the account
    if (accounts.ownerOf(bidderId) != msg.sender) revert DA_SenderNotOwner();

    // margin is buffer margin for solvent auction, maintenance margin for insolvent auction
    (bool canTerminate, int markToMarket, int margin) = getAuctionStatus(accountId);

    if (canTerminate) revert DA_AuctionShouldBeTerminated();

    if (auctions[accountId].insolvent) {
      finalPercentage = percentOfAccount;

      // the account is insolvent when the bid price for the account falls below zero
      // someone get paid from security module to take on the risk
      uint currentPayout = _getInsolventAuctionPayout(accountId);
      cashToBidder = currentPayout.multiplyDecimal(finalPercentage);
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
      // MtM is expected to be negative

      int bidPrice = _getSolventAuctionBidPrice(accountId, markToMarket);

      if (bidPrice <= 0) revert DA_SolventAuctionEnded();

      // todo: if it changes from fast to slow, maybe lock withdraw in cash
      (uint discount,) = _getDiscountPercentage(auctions[accountId].startTime, block.timestamp);

      // calculate tha max proportion of the portfolio that can be liquidated
      uint pMax = _getMaxProportion(markToMarket, margin, discount); // discount

      finalPercentage = percentOfAccount > pMax ? pMax : percentOfAccount;

      cashFromBidder = bidPrice.toUint256().multiplyDecimal(finalPercentage); // bid * f_max
    }

    // risk manager transfers portion of the account to the bidder, liquidator pays cash to accountId
    ILiquidatableManager(address(accounts.manager(accountId))).executeBid(
      accountId, bidderId, finalPercentage, auctions[accountId].percentageLeft, cashFromBidder
    );

    auctions[accountId].percentageLeft -= finalPercentage;

    emit Bid(accountId, bidderId, finalPercentage, cashFromBidder);

    // terminating the auction if the account is back above water
    (bool canTerminateAfter,,) = getAuctionStatus(accountId);
    if (canTerminateAfter) {
      _terminateAuction(accountId);
    }
  }

  /**
   * @notice anyone can come in during the auction to supply a scenario ID that will make the IM worse
   * @param scenarioId new scenarioId
   */
  function updateScenarioId(uint accountId, uint scenarioId) external {
    if (!auctions[accountId].ongoing) revert DA_AuctionNotStarted();

    // check if the new scenarioId is worse than the current one
    (int newMargin,,) = _getMarginAndMarkToMarket(accountId, scenarioId);
    (int currentMargin,,) = _getMarginAndMarkToMarket(accountId, auctions[accountId].scenarioId);

    if (newMargin >= currentMargin) revert DA_ScenarioIdNotWorse();

    auctions[accountId].scenarioId = scenarioId;
    emit ScenarioIdUpdated(accountId, scenarioId);
  }

  /**
   * @notice Function used to begin insolvency logic for an auction that started as solvent
   * @dev This function can only be called on auctions that has already started as solvent
   * @param accountId the accountID being liquidated
   */
  function convertToInsolventAuction(uint accountId) external {
    uint scenarioId = auctions[accountId].scenarioId;
    (int maintenanceMargin, int bufferMargin, int markToMarket) = _getMarginAndMarkToMarket(accountId, scenarioId);
    if (auctions[accountId].insolvent) {
      revert DA_AuctionAlreadyInInsolvencyMode();
    }
    if (_getSolventAuctionBidPrice(accountId, markToMarket) > 0) {
      revert DA_OngoingSolventAuction();
    }

    if (maintenanceMargin >= 0) {
      revert DA_AccountIsAboveMaintenanceMargin();
    }

    _startInsolventAuction(accountId, scenarioId, bufferMargin);
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
      revert DA_SolventAuctionCannotIncrement();
    }

    uint lastIncrement = auction.lastStepUpdate;
    if (block.timestamp <= lastIncrement + insolventAuctionParams.coolDown && lastIncrement != 0) {
      revert DA_InCoolDown();
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
    (bool canTerminate,,) = getAuctionStatus(accountId);
    if (!canTerminate) revert DA_AuctionCannotTerminate();
    _terminateAuction(accountId);
  }

  /**
   * @notice Return true if an auction can be terminated (back above water)
   * @dev for solvent auction: if IM > 0
   * @dev for insolvent auction: if MM > 0
   * @param accountId ID of the account to check
   */
  function getAuctionStatus(uint accountId) public view returns (bool canTerminate, int markToMarket, int netMargin) {
    if (!auctions[accountId].ongoing) revert DA_NotOngoingAuction();

    if (auctions[accountId].insolvent) {
      // get maintenance margin and mark to market
      (netMargin,, markToMarket) = _getMarginAndMarkToMarket(accountId, auctions[accountId].scenarioId);
    } else {
      // get buffer margin and mark to market
      (, netMargin, markToMarket) = _getMarginAndMarkToMarket(accountId, auctions[accountId].scenarioId);
    }

    canTerminate = netMargin > 0;
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
   * @notice External view to get the maximum size of the portfolio that could be bought at the current price
   * @param accountId the id of the account being liquidated
   * @return uint the proportion of the portfolio that could be bought at the current price
   */
  function getMaxProportion(uint accountId, uint scenarioId) external view returns (uint) {
    (, int bufferMargin, int markToMarket) = _getMarginAndMarkToMarket(accountId, scenarioId);

    if (markToMarket < 0) revert DA_SolventAuctionEnded();

    (uint discount,) = _getDiscountPercentage(auctions[accountId].startTime, block.timestamp);

    return _getMaxProportion(markToMarket, bufferMargin, discount);
  }

  /**
   * @notice gets the current bid price for a particular auction at the current block
   * @dev returns the current bid price for a particular auction
   * @param accountId Id of account being liquidated
   * @return int the current bid price for the auction
   */
  function getCurrentBidPrice(uint accountId) external view returns (int) {
    bool insolvent = auctions[accountId].insolvent;
    if (!insolvent) {
      (,, int markToMarket) = _getMarginAndMarkToMarket(accountId, auctions[accountId].scenarioId);
      return _getSolventAuctionBidPrice(accountId, markToMarket);
    } else {
      // the payout is the positive amount security module will pay the liquidator (bidder)
      // which is a "negative" bid price
      return -_getInsolventAuctionPayout(accountId).toInt256();
    }
  }

  function getDiscountPercentage(uint startTime, uint current) external view returns (uint, bool) {
    return _getDiscountPercentage(startTime, current);
  }

  ////////////////////
  //    internal    //
  ////////////////////

  /**
   * @notice Starts an auction that starts with a positive upper bound
   * @dev Function is here to break up the logic for insolvent and solvent auctions
   * @param accountId The id of the account being liquidated
   */
  function _startSolventAuction(uint accountId, uint scenarioId, int markToMarket, uint fee) internal {
    auctions[accountId] = Auction({
      accountId: accountId,
      scenarioId: scenarioId,
      insolvent: false,
      ongoing: true,
      startTime: block.timestamp,
      percentageLeft: 1e18,
      stepSize: 0,
      stepInsolvent: 0,
      lastStepUpdate: 0
    });

    emit SolventAuctionStarted(accountId, scenarioId, markToMarket, fee);
  }

  /**
   * @notice Explain to an end user what this does
   * @dev Explain to a developer any extra details
   * @param lowerBound negative amount in cash, -100e18 means the SM will pay out $100 CASH at most
   * @param accountId the id of the account that is being liquidated
   */
  function _startInsolventAuction(uint accountId, uint scenarioId, int lowerBound) internal {
    // decrease value every step
    uint numSteps = insolventAuctionParams.totalSteps;
    uint stepSize = IntLib.abs(lowerBound) / numSteps;

    auctions[accountId] = Auction({
      accountId: accountId,
      scenarioId: scenarioId,
      insolvent: true,
      ongoing: true,
      startTime: block.timestamp,
      percentageLeft: 1e18,
      stepSize: stepSize,
      stepInsolvent: 0,
      lastStepUpdate: block.timestamp
    });
    emit InsolventAuctionStarted(accountId, numSteps, stepSize);
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

  /////////////////////////
  //   internal  View    //
  /////////////////////////

  /**
   * @dev get the fee that should be transferred to the security module
   * @dev this function should only be called in solvent auction
   */
  function _getLiquidationFee(int markToMarket, int bufferMargin) internal view returns (uint fee) {
    uint maxProportion = _getMaxProportion(markToMarket, bufferMargin, 1e18);

    fee =
      maxProportion.multiplyDecimal(IntLib.abs(markToMarket)).multiplyDecimal(solventAuctionParams.liquidatorFeeRate);
  }

  /**
   * @notice Gets the maximum size of the portfolio that could be bought at the current price
   * @dev assuming negative BM and positive MtM, the formula for max portion is:
   *
   *                        BM
   *    f = ----------------------------------
   *         BM - MtM * discount_percentage
   *
   *
   * @param bufferMargin expect to be negative
   * @param discountPercentage the discount percentage of MtM the auction is offering at (dropping from 98% to 0%)
   * @return uint the proportion of the portfolio that could be bought at the current price
   */
  function _getMaxProportion(int markToMarket, int bufferMargin, uint discountPercentage) internal pure returns (uint) {
    int denominator = bufferMargin - (markToMarket.multiplyDecimal(int(discountPercentage)));

    return bufferMargin.divideDecimal(denominator).toUint256();
  }

  /**
   * @dev get discount percentage
   * the discount percentage decay from startingMtMPercentage to fastAuctionCutoffPercentage during the fast auction
   * then decay from fastAuctionCutoffPercentage to 0 during the slow auction
   */
  function _getDiscountPercentage(uint startTimestamp, uint currentTimestamp)
    internal
    view
    returns (uint discount, bool isFast)
  {
    SolventAuctionParams memory params = solventAuctionParams;

    uint timeElapsed = currentTimestamp - startTimestamp;

    // still during the fast auction
    if (timeElapsed < params.fastAuctionLength) {
      uint totalChangeInFastAuction = params.startingMtMPercentage - params.fastAuctionCutoffPercentage;
      discount = params.startingMtMPercentage
        - totalChangeInFastAuction.multiplyDecimal(timeElapsed).divideDecimal(params.fastAuctionLength);
      isFast = true;
    } else if (timeElapsed > params.fastAuctionLength + params.slowAuctionLength) {
      // whole solvent auction is over
      discount = 0;
      isFast = false;
    } else {
      uint timeElapsedInSlow = timeElapsed - params.fastAuctionLength;
      discount = params.fastAuctionCutoffPercentage
        - uint(params.fastAuctionCutoffPercentage).multiplyDecimal(timeElapsedInSlow).divideDecimal(
          params.slowAuctionLength
        );
      isFast = false;
    }
  }

  function _getMarginAndMarkToMarket(uint accountId, uint scenarioId) internal view returns (int, int, int) {
    address manager = address(accounts.manager(accountId));
    (int maintenanceMargin, int markToMarket) =
      ILiquidatableManager(manager).getMarginAndMarkToMarket(accountId, false, scenarioId);
    // derive Buffer margin from maintenance margin and mark to market
    int mmBuffer = maintenanceMargin - markToMarket; // a negative number added to the mtm to become maintenance margin

    // a more conservative buffered margin that we liquidate to
    int bufferMargin = maintenanceMargin + mmBuffer.multiplyDecimal(bufferMarginPercentage);

    return (maintenanceMargin, bufferMargin, markToMarket);
  }

  /**
   * @notice gets the current bid price for a solvent auction at the current block
   * @dev invariant: returned bids should always be positive
   * @param accountId the uint id related to the auction
   * @return int the current bid price for the auction
   */
  function _getSolventAuctionBidPrice(uint accountId, int markToMarket) internal view returns (int) {
    Auction memory auction = auctions[accountId];

    if (!auction.ongoing) revert DA_AuctionNotStarted();

    uint totalLength = solventAuctionParams.fastAuctionLength + solventAuctionParams.slowAuctionLength;
    if (block.timestamp > auction.startTime + totalLength) return 0;

    // calculate discount percentage
    (uint discount,) = _getDiscountPercentage(auctions[accountId].startTime, block.timestamp); //getDiscount;

    int bidPrice = markToMarket.multiplyDecimal(int(discount));
    return bidPrice;
  }

  /**
   * @dev return the value that the security module will pay the liquidator
   * @dev this can be translated to a "negative" bid price.
   *
   * @return payout: a positive number indicating how much the security module will pay the liquidator
   */
  function _getInsolventAuctionPayout(uint accountId) internal view returns (uint) {
    if (!auctions[accountId].ongoing) revert DA_AuctionNotStarted();

    return auctions[accountId].stepSize * auctions[accountId].stepInsolvent;
  }
}
