// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

// interfaces
import {ILiquidatableManager} from "../interfaces/ILiquidatableManager.sol";
import {ISecurityModule} from "../interfaces/ISecurityModule.sol";
import {ICashAsset} from "../interfaces/ICashAsset.sol";
import {IDutchAuction} from "../interfaces/IDutchAuction.sol";
import {SubAccounts} from "../SubAccounts.sol";

// inherited
import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/math/SignedMath.sol";
import "lyra-utils/decimals/DecimalMath.sol";
import "lyra-utils/decimals/SignedDecimalMath.sol";
import "openzeppelin/access/Ownable2Step.sol";

/**
 * @title Dutch Auction
 * @author Lyra
 * @notice This module is used to liquidate an account that does not meet the margin requirements
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
 * the price of portfolio went from 0 to MtM * scaler (negative)
 * can be un-flagged if maintenance margin > 0
 */
contract DutchAuction is IDutchAuction, Ownable2Step {
  using SafeCast for int;
  using SafeCast for uint;
  using SignedDecimalMath for int;
  using DecimalMath for uint;

  /// @dev The security module that will help pay out for insolvent auctions
  ISecurityModule public immutable securityModule;

  /// @dev The cash asset address, will be used to socialize losses when there's systematic insolvency
  ICashAsset public immutable cash;

  /// @dev The accounts contract for resolving address to accountIds
  SubAccounts public immutable subAccounts;

  ///////////////////////
  //  State Variables  //
  ///////////////////////

  /// @dev Help defines buffer margin: maintenance margin - bufferPercentage * (maintenance margin - mtm)
  int public bufferMarginPercentage;

  /// @dev The number of insolvent auctions that are blocking withdraws
  uint public insolventAuctionCount;

  /// @dev AccountId => Auction for when an auction is started
  mapping(uint accountId => Auction) public auctions;

  /// @dev The parameters for the solvent auction phase
  AuctionParams public auctionParams;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(SubAccounts _subAccounts, ISecurityModule _securityModule, ICashAsset _cash) Ownable2Step() {
    subAccounts = _subAccounts;
    securityModule = _securityModule;
    cash = _cash;
  }

  ////////////////////////
  //     Owner-only     //
  ////////////////////////

  /**
   * @notice Set buffer margin that will be used to determine the target margin level we liquidate to
   * @dev if set to 0, we liquidate to maintenance margin. If set to 0.3, approximately to initial margin for PMRM (IM = MM*1.3)
   */
  function setBufferMarginPercentage(int _bufferMarginPercentage) external onlyOwner {
    if (_bufferMarginPercentage > 4e18) revert DA_InvalidBufferMarginParameter();
    bufferMarginPercentage = _bufferMarginPercentage;

    emit BufferMarginPercentageSet(_bufferMarginPercentage);
  }

  /**
   * @notice Sets the dutch Auction Parameters
   * @dev This function is used to set the parameters for the fast and slow solvent auctions
   * @param _params New parameters
   */
  function setAuctionParams(AuctionParams memory _params) external onlyOwner {
    if (
      _params.startingMtMPercentage > 1e18 // cannot start with > 100% of mark to market
        || _params.liquidatorFeeRate > 0.1e18 // liquidator fee cannot be higher than 10%
        || _params.fastAuctionCutoffPercentage > _params.startingMtMPercentage
    ) revert DA_InvalidParameter();

    auctionParams = _params;

    emit AuctionParamsSet(_params);
  }

  /////////////////////
  //  Begin Auction  //
  /////////////////////

  /**
   * @dev anyone can start an auction for an account
   * @param accountId The id of the account being liquidated
   * @param scenarioId id to compute the IM with for PMRM, ignored for standard manager
   */
  function startAuction(uint accountId, uint scenarioId) external {
    _startAuction(accountId, scenarioId);
  }

  function _startAuction(uint accountId, uint scenarioId) internal {
    // settle pending interest rate on an account
    ILiquidatableManager accountManager = ILiquidatableManager(address(subAccounts.manager(accountId)));
    accountManager.settleInterest(accountId);
    accountManager.settlePerpsWithIndex(accountId);

    (int maintenanceMargin, int bufferMargin, int markToMarket) = _getMarginAndMarkToMarket(accountId, scenarioId);

    // can only start auction if maintenance margin < 0. (If > 0 it's still well collateralized)
    if (maintenanceMargin >= 0) revert DA_AccountIsAboveMaintenanceMargin();

    if (auctions[accountId].ongoing) revert DA_AuctionAlreadyStarted();

    if (markToMarket > 0) {
      uint fee = 0;
      // charge the account a fee to security module
      // fee is a percentage of percentage of mtm, so paying fee will never make mtm < 0
      fee = _getLiquidationFee(markToMarket, bufferMargin);
      if (fee > 0) {
        accountManager.payLiquidationFee(accountId, securityModule.accountId(), fee);
      }

      // solvent auction goes from mark to market * static discount -> 0
      _startSolventAuction(accountId, scenarioId, markToMarket, fee);
    } else {
      _startInsolventAuction(accountId, scenarioId, bufferMargin);
    }
  }

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
      reservedCash: 0
    });

    emit SolventAuctionStarted(accountId, scenarioId, markToMarket, fee);
  }

  /**
   * @dev Starts an insolvent auction
   * @param accountId The id of the account that is being liquidated
   */
  function _startInsolventAuction(uint accountId, uint scenarioId, int markToMarket) internal {
    insolventAuctionCount += 1;
    auctions[accountId] = Auction({
      accountId: accountId,
      scenarioId: scenarioId,
      insolvent: true,
      ongoing: true,
      startTime: block.timestamp,
      percentageLeft: 1e18,
      reservedCash: 0
    });
    emit InsolventAuctionStarted(accountId, scenarioId, markToMarket);
  }

  /////////////////////////
  // Update live auction //
  /////////////////////////

  /**
   * @notice anyone can come in during the auction to supply a scenario ID that will make the IM worse
   * @param scenarioId new scenarioId
   */
  function updateScenarioId(uint accountId, uint scenarioId) external {
    if (!auctions[accountId].ongoing) revert DA_AuctionNotStarted();

    // check if the new scenarioId is worse than the current one
    // TODO: add a test for how this works for basis (should revert/not allow updates as margin is the "same")
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
    // TODO: THIS WILL REVERT IF MTM < 0 -> CANNOT CONVERT AUCTION. Have to terminate -> restart
    //  - todo: test to show this flow/check that terminate will work in this situation
    // Could do if (mtm > 0 && _getSolvent[...]) to resolve
    if (_getSolventAuctionBidPrice(accountId, markToMarket) > 0) {
      revert DA_OngoingSolventAuction();
    }

    if (maintenanceMargin >= 0) {
      revert DA_AccountIsAboveMaintenanceMargin();
    }

    _startInsolventAuction(accountId, scenarioId, bufferMargin);
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

  ////////////////////////
  //   Auction Bidding  //
  ////////////////////////

  /**
   * @notice a user submits a bid for a particular auction
   * @dev Takes in the auction and returns the account id
   * @param accountId Account ID of the liquidated account
   * @param bidderId Account ID of bidder, must be owned by msg.sender
   * @param percentOfAccount Percentage of account to liquidate, in 18 decimals
   * @param maxCash Maximum amount of cash to be paid from bidder to liquidated account. This param is ignored if set to 0, or in insolvent mode
   * @param expectedLastTradeId The last trade id that the bidder expects the account to be on. Can be used to prevent frontrun
   * @return finalPercentage percentage of portfolio being liquidated
   * @return cashFromBidder Amount of cash paid from bidder to liquidated account
   * @return cashToBidder Amount of cash paid from security module for bidder to take on the risk
   */
  function bid(uint accountId, uint bidderId, uint percentOfAccount, uint maxCash, uint expectedLastTradeId)
    external
    returns (uint finalPercentage, uint cashFromBidder, uint cashToBidder)
  {
    if (percentOfAccount > DecimalMath.UNIT || percentOfAccount == 0) {
      revert DA_InvalidPercentage();
    }

    // check if the last trade id is the same as expected
    if (expectedLastTradeId != 0 && subAccounts.lastAccountTradeId(accountId) != expectedLastTradeId) {
      revert DA_InvalidLastTradeId();
    }

    ILiquidatableManager accountManager = ILiquidatableManager(address(subAccounts.manager(accountId)));
    // Settle perps to make sure all PNL is realized in cash.
    accountManager.settleInterest(accountId);
    accountManager.settlePerpsWithIndex(accountId);

    // get bidder address and make sure that they own the account
    if (subAccounts.ownerOf(bidderId) != msg.sender) revert DA_SenderNotOwner();

    // margin is buffer margin for solvent auction, maintenance margin for insolvent auction
    (bool canTerminate, int markToMarket, int margin) = getAuctionStatus(accountId);

    if (canTerminate) revert DA_AuctionShouldBeTerminated();

    bool canTerminateAfterwards;
    if (auctions[accountId].insolvent) {
      (canTerminateAfterwards, finalPercentage, cashToBidder) =
        _bidOnInsolventAuction(accountId, bidderId, percentOfAccount, margin);
    } else {
      (canTerminateAfterwards, finalPercentage, cashFromBidder) =
        _bidOnSolventAuction(accountId, bidderId, percentOfAccount, margin, markToMarket);

      // if cash spent is higher than specified, revert the call
      if (maxCash > 0 && cashFromBidder > maxCash) revert DA_MaxCashExceeded();
    }

    if (canTerminateAfterwards) {
      _terminateAuction(accountId);
    }

    emit Bid(accountId, bidderId, finalPercentage, cashFromBidder, cashToBidder);
  }

  /**
   * @param accountId Account being liquidated
   * @param bidderId Account getting paid from security module to take the liquidated account
   * @param percentOfAccount the percentage of the original portfolio that was put on auction
   * @return canTerminate can the auction be terminated afterwards
   * @return percentLiquidated the percentage of the original portfolio account that was actually liquidated
   */
  function _bidOnSolventAuction(
    uint accountId,
    uint bidderId,
    uint percentOfAccount,
    int bufferMargin,
    int markToMarket
  ) internal returns (bool canTerminate, uint percentLiquidated, uint cashFromBidder) {
    percentLiquidated = percentOfAccount;

    // calculate the max percentage of "current portfolio" that can be liquidated. Priced using original portfolio.
    int bidPrice = _getSolventAuctionBidPrice(accountId, markToMarket);
    if (bidPrice <= 0) revert DA_SolventAuctionEnded();

    Auction storage currentAuction = auctions[accountId];

    (uint discount,) = _getDiscountPercentage(currentAuction.startTime, block.timestamp);

    // max percentage of the "current" portfolio that can be liquidated
    uint maxOfCurrent = _getMaxProportion(markToMarket, bufferMargin, discount, currentAuction.reservedCash);

    // calculate percentage of the original portfolio, to percentage of current portfolio
    uint convertedPercentage = percentOfAccount.divideDecimal(currentAuction.percentageLeft);
    if (convertedPercentage >= maxOfCurrent) {
      convertedPercentage = maxOfCurrent;
      percentLiquidated = convertedPercentage.multiplyDecimal(currentAuction.percentageLeft);
      canTerminate = true;
    }

    cashFromBidder = bidPrice.toUint256().multiplyDecimal(percentLiquidated);

    int bidderCashBalance = subAccounts.getBalance(bidderId, cash, 0);
    if (bidderCashBalance.toUint256() < cashFromBidder) revert DA_InsufficientCash();

    // risk manager transfers portion of the account to the bidder, liquidator pays cash to accountId
    ILiquidatableManager(address(subAccounts.manager(accountId))).executeBid(
      accountId, bidderId, convertedPercentage, cashFromBidder, currentAuction.reservedCash
    );

    currentAuction.reservedCash += cashFromBidder;
    currentAuction.percentageLeft -= percentLiquidated;

    return (canTerminate, percentLiquidated, cashFromBidder);
  }

  /**
   * @dev Bidder got paid to take on an insolvent account
   * @param accountId Account being liquidated
   * @param bidderId Account getting paid from security module to take the liquidated account
   * @param percentOfAccount the percentage of the original portfolio that was put on auction
   */
  function _bidOnInsolventAuction(uint accountId, uint bidderId, uint percentOfAccount, int maintenanceMargin)
    internal
    returns (bool canTerminate, uint percentLiquidated, uint cashToBidder)
  {
    Auction storage currentAuction = auctions[accountId];

    uint percentageOfOriginalLeft = currentAuction.percentageLeft;
    percentLiquidated = percentOfAccount > percentageOfOriginalLeft ? percentageOfOriginalLeft : percentOfAccount;

    // the account is insolvent when the bid price for the account falls below zero
    // someone get paid from security module to take on the risk
    cashToBidder =
      (-_getInsolventAuctionBidPrice(accountId, maintenanceMargin)).toUint256().multiplyDecimal(percentLiquidated);

    // we first ask the security module to compensate the bidder
    uint amountPaid = securityModule.requestPayout(bidderId, cashToBidder);
    // if amount paid is less than we requested: we trigger socialize losses on cash asset (which will print cash)
    if (cashToBidder > amountPaid) {
      uint loss = cashToBidder - amountPaid;
      cash.socializeLoss(loss, bidderId);
    }

    // risk manager transfers portion of the account to the bidder, liquidator pays 0
    uint percentageOfCurrent = percentLiquidated.divideDecimal(percentageOfOriginalLeft);

    currentAuction.percentageLeft -= percentLiquidated;

    ILiquidatableManager(address(subAccounts.manager(accountId))).executeBid(
      accountId, bidderId, percentageOfCurrent, 0, currentAuction.reservedCash
    );

    // ensure bidder is solvent (maintenance margin > 0)
    (int bidderMM,,) = _getMarginAndMarkToMarket(bidderId, currentAuction.scenarioId);
    if (bidderMM < 0) revert DA_BidderInsolvent();

    canTerminate = currentAuction.percentageLeft == 0;
  }

  ////////////////////////
  //       Views        //
  ////////////////////////

  /**
   * @notice Return true if an auction can be terminated (back above water)
   * @dev for solvent auction: if BM > 0
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
      // Handle edge case where MTM moves a lot and then reserved cash is worth more than MTM.
      // In this case, the original portfolio margin would've been negative, but reserved cash is held by the account.
      // We terminate the auction and allow it to restart in this rare case. In the case MTM < 0, we would start an
      // insolvent auction.
      if (markToMarket > 0 && int(auctions[accountId].reservedCash) > markToMarket) {
        return (true, markToMarket, netMargin);
      }
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

    return _getMaxProportion(markToMarket, bufferMargin, discount, auctions[accountId].reservedCash);
  }

  /**
   * @notice gets the current bid price for a particular auction at the current block
   * @dev returns the current bid price for a particular auction
   * @param accountId Id of account being liquidated
   * @return int the current bid price for the auction
   */
  function getCurrentBidPrice(uint accountId) external view returns (int) {
    bool insolvent = auctions[accountId].insolvent;
    (int maintenanceMargin,, int markToMarket) = _getMarginAndMarkToMarket(accountId, auctions[accountId].scenarioId);
    if (!insolvent) {
      return _getSolventAuctionBidPrice(accountId, markToMarket);
    } else {
      // this function returns a negative bid price
      return _getInsolventAuctionBidPrice(accountId, maintenanceMargin);
    }
  }

  function getDiscountPercentage(uint startTime, uint current) external view returns (uint, bool) {
    return _getDiscountPercentage(startTime, current);
  }

  function getMarginAndMarkToMarket(uint accountId, uint scenarioId) external view returns (int, int, int) {
    return _getMarginAndMarkToMarket(accountId, scenarioId);
  }

  /**
   * @dev return true if the withdraw should be blocked
   */
  function getIsWithdrawBlocked() external view returns (bool) {
    return insolventAuctionCount > 0;
  }

  //////////////////////////////
  //    Internal Functions    //
  //////////////////////////////

  /**
   * @notice Internal function to terminate an auction
   * @dev Changes the value of an auction and flags that it can no longer be bid on
   * @param accountId The accountId of account that is being liquidated
   */
  function _terminateAuction(uint accountId) internal {
    Auction storage auction = auctions[accountId];
    auction.ongoing = false;

    if (auction.insolvent) {
      insolventAuctionCount -= 1;
    }

    emit AuctionEnded(accountId, block.timestamp);
  }

  /////////////////////////
  //   Internal Views    //
  /////////////////////////

  /**
   * @dev get the fee that should be transferred to the security module
   * @dev this function should only be called in solvent auction
   */
  function _getLiquidationFee(int markToMarket, int bufferMargin) internal view returns (uint fee) {
    uint maxProportion = _getMaxProportion(markToMarket, bufferMargin, 1e18, 0);
    fee = maxProportion.multiplyDecimal(SignedMath.abs(markToMarket)).multiplyDecimal(auctionParams.liquidatorFeeRate);
  }

  /**
   * @notice Gets the maximum size of the portfolio that could be bought at the current price
   * @dev assuming negative BM and positive MtM, the formula for max portion is:
   *
   *                   BM
   *    f = --------------------------
   *         BM - MtM * d - R * (1-d)
   *
   *  where:
   *    BM is the buffer margin
   *    MtM is the mark to market
   *    d is the discount percentage
   *    R is the reserved cash
   * @param bufferMargin expect to be negative
   * @param discountPercentage the discount percentage of MtM the auction is offering at (dropping from 98% to 0%)
   * @return uint the proportion of the portfolio that could be bought at the current price
   */
  function _getMaxProportion(int markToMarket, int bufferMargin, uint discountPercentage, uint reservedCash)
    internal
    pure
    returns (uint)
  {
    if (bufferMargin > 0) {
      bufferMargin = 0;
    }
    int denominator = bufferMargin - (markToMarket.multiplyDecimal(int(discountPercentage)))
      - int(reservedCash.multiplyDecimal(1e18 - discountPercentage));

    return bufferMargin.divideDecimal(denominator).toUint256();
  }

  /**
   * @notice Get discount percentage
   * @dev the discount percentage decay from startingMtMPercentage to fastAuctionCutoffPercentage during the fast auction
   *      then decay from fastAuctionCutoffPercentage to 0 during the slow auction
   */
  function _getDiscountPercentage(uint startTimestamp, uint currentTimestamp)
    internal
    view
    returns (uint discount, bool isFast)
  {
    AuctionParams memory params = auctionParams;

    uint timeElapsed = currentTimestamp - startTimestamp;

    // still during the fast auction
    if (timeElapsed < params.fastAuctionLength) {
      uint totalChangeInFastAuction = params.startingMtMPercentage - params.fastAuctionCutoffPercentage;
      discount = params.startingMtMPercentage - totalChangeInFastAuction * timeElapsed / params.fastAuctionLength;
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
    address manager = address(subAccounts.manager(accountId));
    (int maintenanceMargin, int markToMarket) =
      ILiquidatableManager(manager).getMarginAndMarkToMarket(accountId, false, scenarioId);
    // derive Buffer margin from maintenance margin and mark to market
    int mmBuffer = maintenanceMargin - markToMarket; // a negative number added to the mtm to become maintenance margin
    // TODO: invariant test -> add an assertion mmBuffer is negative
    // a more conservative buffered margin that we liquidate to
    int bufferMargin = maintenanceMargin + mmBuffer.multiplyDecimal(bufferMarginPercentage);

    return (maintenanceMargin, bufferMargin, markToMarket);
  }

  /**
   * @notice Gets the current bid price for a solvent auction at the current block
   * @dev invariant: returned bids should always be positive
   * @param accountId the uint id related to the auction
   * @return int the current bid price for the auction
   */
  function _getSolventAuctionBidPrice(uint accountId, int markToMarket) internal view returns (int) {
    Auction memory auction = auctions[accountId];

    if (!auction.ongoing) revert DA_AuctionNotStarted();

    uint totalLength = auctionParams.fastAuctionLength + auctionParams.slowAuctionLength;
    if (block.timestamp > auction.startTime + totalLength) return 0;

    // calculate discount percentage
    (uint discount,) = _getDiscountPercentage(auctions[accountId].startTime, block.timestamp); //getDiscount;

    if (int(auction.reservedCash) > markToMarket) {
      revert DA_ReservedCashGreaterThanMtM();
    }
    int scaledMtM = (markToMarket - int(auction.reservedCash)).divideDecimal(int(auction.percentageLeft));

    return scaledMtM.multiplyDecimal(int(discount));
  }

  /**
   * @dev Return a "negative" bid price. Meaning this is how much the SM is paying the liquidator to take on the risk
   * @dev If MtM is 0, return 0.
   * @return bidPrice a negative number,
   */
  function _getInsolventAuctionBidPrice(uint accountId, int maintenanceMargin) internal view returns (int) {
    if (!auctions[accountId].ongoing) revert DA_AuctionNotStarted();
    if (maintenanceMargin > 0) return 0;

    uint timeElapsed = block.timestamp - auctions[accountId].startTime;
    if (timeElapsed >= auctionParams.insolventAuctionLength) {
      return maintenanceMargin;
    } else {
      // scaler is linearly growing from 1 to endingMtMScaler, over the length of the auction
      return
        int(timeElapsed).multiplyDecimal(maintenanceMargin).divideDecimal(int(auctionParams.insolventAuctionLength));
    }
  }
}
