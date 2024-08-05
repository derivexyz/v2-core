// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

// interfaces
import {ILiquidatableManager} from "../interfaces/ILiquidatableManager.sol";
import {ISecurityModule} from "../interfaces/ISecurityModule.sol";
import {ICashAsset} from "../interfaces/ICashAsset.sol";
import {IDutchAuction} from "../interfaces/IDutchAuction.sol";
import {ISubAccounts} from "../interfaces/ISubAccounts.sol";

// inherited
import "openzeppelin/security/ReentrancyGuard.sol";
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
 * insolvent auction will kick off if no one bid on the solvent auction, meaning no one wants to take the portfolio even
 * if it's given for free, or, it can be started if mark to market value of a portfolio is negative.
 *
 * the insolvent auction that will pay out from security module or print cash to the liquidator to take on the position
 * the price of portfolio goes from 0 to MM
 * can be un-flagged if maintenance margin > 0
 */
contract DutchAuction is IDutchAuction, Ownable2Step, ReentrancyGuard {
  using SafeCast for int;
  using SafeCast for uint;
  using SignedDecimalMath for int;
  using DecimalMath for uint;

  /// @dev The security module that will help pay out for insolvent auctions
  ISecurityModule public immutable securityModule;

  /// @dev The cash asset address, will be used to socialize losses when there's systematic insolvency
  ICashAsset public immutable cash;

  /// @dev The accounts contract for resolving address to accountIds
  ISubAccounts public immutable subAccounts;

  ///////////////////////
  //  State Variables  //
  ///////////////////////

  /// @dev The sum of cached MMs for all insolvent auctions
  uint public totalInsolventMM;

  /// @dev The subaccount of the SM, to track the total balance against the totalInsolventMM
  uint public smAccount;

  /// @dev AccountId => Auction for when an auction is started
  mapping(uint accountId => Auction) public auctions;

  /// @dev The parameters for the solvent auction phase
  AuctionParams public auctionParams;

  mapping(address => bool) public managerWhitelisted;

  /// @dev Threshold below which an account gets fully liquidated instead of partially
  int public mtmCutoff;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(ISubAccounts _subAccounts, ISecurityModule _securityModule, ICashAsset _cash) Ownable2Step() {
    subAccounts = _subAccounts;
    securityModule = _securityModule;
    cash = _cash;
  }

  ////////////////////////
  //     Owner-only     //
  ////////////////////////

  /**
   * @notice Sets the dutch Auction Parameters
   * @dev This function is used to set the parameters for the fast and slow solvent auctions
   * @param _params New parameters
   */
  function setAuctionParams(AuctionParams memory _params) external onlyOwner {
    if (
      _params.startingMtMPercentage > 1e18 // cannot start with > 100% of mark to market
        || _params.liquidatorFeeRate > 0.1e18 // liquidator fee cannot be higher than 10%
        || _params.fastAuctionCutoffPercentage > _params.startingMtMPercentage || _params.bufferMarginPercentage > 4e18 // buffer margin cannot be higher than 400%
    ) revert DA_InvalidParameter();

    auctionParams = _params;

    emit AuctionParamsSet(_params);
  }

  /**
   * @notice Sets the threshold, below which a bid can liquidate 100% of the account
   */
  function setMtmCutoff(int _mtmCutoff) external onlyOwner {
    if (_mtmCutoff > 1_000e18) revert DA_InvalidParameter();

    mtmCutoff = _mtmCutoff;

    emit MtmCutOffSet(_mtmCutoff);
  }

  /**
   * @notice Sets the threshold, below which an auction will block cash withdraw to prevent bank-run
   */
  function setSMAccount(uint _smAccount) external onlyOwner {
    smAccount = _smAccount;

    emit SMAccountSet(_smAccount);
  }

  /**
   * @notice Enables or disables starting and bidding on auctions for a given manager
   */
  function setWhitelistManager(address manager, bool whitelisted) external onlyOwner {
    managerWhitelisted[manager] = whitelisted;

    emit ManagerWhitelisted(manager, whitelisted);
  }

  /////////////////////
  //  Begin Auction  //
  /////////////////////

  /**
   * @dev anyone can start an auction for an account
   * @param accountId The id of the account being liquidated
   * @param scenarioId id to compute the IM with for PMRM, ignored for standard manager
   */
  function startAuction(uint accountId, uint scenarioId) external nonReentrant {
    _startAuction(accountId, scenarioId);
  }

  function _startAuction(uint accountId, uint scenarioId) internal {
    // settle pending interest rate on an account
    ILiquidatableManager accountManager = ILiquidatableManager(address(subAccounts.manager(accountId)));

    if (!managerWhitelisted[address(accountManager)]) {
      revert DA_NotWhitelistedManager();
    }

    accountManager.settleInterest(accountId);
    accountManager.settlePerpsWithIndex(accountId);

    (int maintenanceMargin, int bufferMargin, int markToMarket) = _getMarginAndMarkToMarket(accountId, scenarioId);

    // can only start auction if maintenance margin < 0. (If > 0 it's still well collateralized)
    if (maintenanceMargin >= 0) revert DA_AccountIsAboveMaintenanceMargin();

    if (auctions[accountId].ongoing) revert DA_AuctionAlreadyStarted();

    if (markToMarket > 0) {
      // charge the account a fee to security module
      // fee is a percentage of percentage of mtm, so paying fee will never make mtm < 0
      uint fee = _getLiquidationFee(markToMarket, bufferMargin);
      if (fee > 0) {
        accountManager.payLiquidationFee(accountId, securityModule.accountId(), fee);
      }

      // solvent auction goes from mark to market * static discount -> 0
      _startSolventAuction(accountId, scenarioId, markToMarket, fee);
    } else {
      _startInsolventAuction(accountId, scenarioId, maintenanceMargin);
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
      cachedMM: 0,
      startTime: block.timestamp,
      reservedCash: 0
    });

    emit SolventAuctionStarted(accountId, scenarioId, markToMarket, fee);
  }

  /**
   * @dev Starts an insolvent auction
   * @param accountId The id of the account that is being liquidated
   */
  function _startInsolventAuction(uint accountId, uint scenarioId, int maintenanceMargin) internal {
    // Track the total MM to pause withdrawals if the SM balance is emptied
    uint insolventMM = (-maintenanceMargin).toUint256();
    totalInsolventMM += insolventMM;

    auctions[accountId] = Auction({
      accountId: accountId,
      scenarioId: scenarioId,
      insolvent: true,
      ongoing: true,
      cachedMM: insolventMM,
      startTime: block.timestamp,
      reservedCash: 0
    });
    emit InsolventAuctionStarted(accountId, scenarioId, maintenanceMargin);
  }

  /////////////////////////
  // Update live auction //
  /////////////////////////

  /**
   * @notice anyone can come in during the auction to supply a scenario ID that will make the IM worse
   * @param scenarioId new scenarioId
   */
  function updateScenarioId(uint accountId, uint scenarioId) external nonReentrant {
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
   * @dev This function can only be called on auctions that have already started as solvent and passed the timer
   * @param accountId the accountID being liquidated
   */
  function convertToInsolventAuction(uint accountId) external nonReentrant {
    uint scenarioId = auctions[accountId].scenarioId;
    (int maintenanceMargin,, int markToMarket) = _getMarginAndMarkToMarket(accountId, scenarioId);

    if (auctions[accountId].insolvent) {
      revert DA_AuctionAlreadyInInsolvencyMode();
    }

    // Note: must terminate auction -> start insolvent auction to convert a solvent auction with mtm < 0 into insolvent
    if (_getSolventAuctionBidPrice(accountId, markToMarket) > 0) {
      revert DA_OngoingSolventAuction();
    }

    if (maintenanceMargin >= 0) {
      revert DA_AccountIsAboveMaintenanceMargin();
    }

    _startInsolventAuction(accountId, scenarioId, maintenanceMargin);
  }

  /**
   * @notice This function can used by anyone to end an auction early
   * @dev This is to allow account owner to cancel the auction after adding more collateral
   * @param accountId the accountId that relates to the auction that is being stepped
   */
  function terminateAuction(uint accountId) external nonReentrant {
    (bool canTerminate,,,) = getAuctionStatus(accountId);
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
   * @param percentOfAccount Percentage of current account to liquidate, in 18 decimals
   * @param priceLimit Maximum amount of cash to be paid from bidder to liquidated account (including negative amounts for insolvent auctions). This param is ignored if set to 0
   * @param expectedLastTradeId The last trade id that the bidder expects the account to be on. Can be used to prevent frontrun
   * @return finalPercentage percentage of portfolio being liquidated
   * @return cashFromBidder Amount of cash paid from bidder to liquidated account
   * @return cashToBidder Amount of cash paid from security module for bidder to take on the risk
   */
  function bid(uint accountId, uint bidderId, uint percentOfAccount, int priceLimit, uint expectedLastTradeId)
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

    if (!managerWhitelisted[address(accountManager)]) {
      revert DA_NotWhitelistedManager();
    }

    if (address(accountManager) != address(subAccounts.manager(bidderId))) {
      revert DA_CannotBidWithDifferentManager();
    }

    // Settle perps to make sure all PNL is realized in cash.
    accountManager.settleInterest(accountId);
    accountManager.settlePerpsWithIndex(accountId);

    // get bidder address and make sure that they own the account
    if (subAccounts.ownerOf(bidderId) != msg.sender) revert DA_SenderNotOwner();

    // margin is buffer margin for solvent auction, maintenance margin for insolvent auction
    (bool canTerminate, int markToMarket, int mm, int bm) = getAuctionStatus(accountId);

    if (canTerminate) revert DA_AuctionShouldBeTerminated();

    bool canTerminateAfterwards;
    if (auctions[accountId].insolvent) {
      (canTerminateAfterwards, finalPercentage, cashToBidder) =
        _bidOnInsolventAuction(accountId, bidderId, percentOfAccount, mm, markToMarket);
      if (priceLimit != 0 && -cashToBidder.toInt256() > priceLimit) revert DA_PriceLimitExceeded();
    } else {
      (canTerminateAfterwards, finalPercentage, cashFromBidder) =
        _bidOnSolventAuction(accountId, bidderId, percentOfAccount, bm, markToMarket);

      // if cash spent is higher than specified, revert the call
      if (priceLimit != 0 && cashFromBidder.toInt256() > priceLimit) revert DA_PriceLimitExceeded();
    }

    if (canTerminateAfterwards) {
      _terminateAuction(accountId);
    }

    emit Bid(accountId, bidderId, finalPercentage, cashFromBidder, cashToBidder);
  }

  /**
   * @param accountId Account being liquidated
   * @param bidderId Account getting paid from security module to take the liquidated account
   * @param percentOfAccount the percentage of the current portfolio being bid on
   * @param bufferMargin the buffer margin of the current portfolio
   * @param markToMarket the mark to market of the current portfolio
   * @return canTerminate can the auction be terminated afterwards
   * @return percentLiquidated the percentage of the current portfolio account that was actually liquidated
   * @return cashFromBidder the amount of cash paid from bidder to liquidated account
   */
  function _bidOnSolventAuction(
    uint accountId,
    uint bidderId,
    uint percentOfAccount,
    int bufferMargin,
    int markToMarket
  ) internal returns (bool canTerminate, uint percentLiquidated, uint cashFromBidder) {
    // calculate the max percentage of "current portfolio" that can be liquidated. Priced using original portfolio.
    int bidPrice = _getSolventAuctionBidPrice(accountId, markToMarket);
    if (bidPrice <= 0) revert DA_SolventAuctionEnded();

    Auction storage currentAuction = auctions[accountId];

    uint discount = _getDiscountPercentage(currentAuction.startTime, block.timestamp);

    // max percentage of the "current" portfolio that can be liquidated
    uint maxOfCurrent = _getMaxProportion(markToMarket, bufferMargin, discount, currentAuction.reservedCash);

    if (percentOfAccount >= maxOfCurrent) {
      percentOfAccount = maxOfCurrent;
      canTerminate = true;
    }

    cashFromBidder = bidPrice.toUint256().multiplyDecimal(percentOfAccount);

    // Bidder must have enough cash to pay for the bid, and enough cash to cover the buffer margin
    _ensureBidderCashBalance(
      bidderId,
      cashFromBidder
        + (SignedMath.abs(bufferMargin - currentAuction.reservedCash.toInt256())).multiplyDecimal(percentOfAccount)
    );

    // risk manager transfers portion of the account to the bidder, liquidator pays cash to accountId
    ILiquidatableManager(address(subAccounts.manager(accountId))).executeBid(
      accountId, bidderId, percentOfAccount, cashFromBidder, currentAuction.reservedCash
    );

    currentAuction.reservedCash += cashFromBidder;

    return (canTerminate, percentOfAccount, cashFromBidder);
  }

  /**
   * @dev Bidder got paid to take on an insolvent account
   * @param accountId Account being liquidated
   * @param bidderId Account getting paid from security module to take the liquidated account
   * @param percentOfAccount the percentage of the current portfolio to be bid on
   * @param maintenanceMargin the maintenance margin of the current portfolio
   * @param markToMarket the mark to market of the current portfolio
   * @return canTerminate can the auction be terminated afterwards
   * @return percentLiquidated the percentage of the current portfolio account that was actually liquidated
   * @return cashToBidder the amount of cash paid from security module to bidder to take on the risk
   */
  function _bidOnInsolventAuction(
    uint accountId,
    uint bidderId,
    uint percentOfAccount,
    int maintenanceMargin,
    int markToMarket
  ) internal returns (bool canTerminate, uint percentLiquidated, uint cashToBidder) {
    Auction storage currentAuction = auctions[accountId];

    // the account is insolvent when the bid price for the account falls below zero
    // someone get paid from security module to take on the risk
    cashToBidder = (-_getInsolventAuctionBidPrice(accountId, maintenanceMargin, markToMarket)).toUint256()
      .multiplyDecimal(percentOfAccount);

    _ensureBidderCashBalance(
      bidderId, SignedMath.abs(maintenanceMargin).multiplyDecimal(percentOfAccount) - cashToBidder
    );

    // we first ask the security module to compensate the bidder
    uint amountPaid = securityModule.requestPayout(bidderId, cashToBidder);
    // if amount paid is less than we requested: we trigger socialize losses on cash asset (which will print cash)
    if (cashToBidder > amountPaid) {
      uint loss = cashToBidder - amountPaid;
      cash.socializeLoss(loss, bidderId);
    }

    ILiquidatableManager(address(subAccounts.manager(accountId))).executeBid(
      accountId, bidderId, percentOfAccount, 0, currentAuction.reservedCash
    );

    // can terminate as soon as someone takes 100% of the account
    return (percentOfAccount == 1e18, percentOfAccount, cashToBidder);
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
  function getAuctionStatus(uint accountId)
    public
    view
    returns (bool canTerminate, int markToMarket, int maintenanceMargin, int bufferMargin)
  {
    if (!auctions[accountId].ongoing) revert DA_NotOngoingAuction();

    uint timeElapsed = block.timestamp - auctions[accountId].startTime;

    // If the auction is insolvent OR the solvent auction has ended (so it can be converted to insolvent)
    if (
      auctions[accountId].insolvent || timeElapsed >= auctionParams.fastAuctionLength + auctionParams.slowAuctionLength
    ) {
      // get maintenance margin and mark to market
      (maintenanceMargin, bufferMargin, markToMarket) =
        _getMarginAndMarkToMarket(accountId, auctions[accountId].scenarioId);
      return (maintenanceMargin >= 0, markToMarket, maintenanceMargin, bufferMargin);
    } else {
      // get buffer margin and mark to market
      (maintenanceMargin, bufferMargin, markToMarket) =
        _getMarginAndMarkToMarket(accountId, auctions[accountId].scenarioId);

      // In the case of a solvent auction falling below MtM, we terminate the auction and restart it as insolvent
      if (markToMarket < 0) {
        return (true, markToMarket, maintenanceMargin, bufferMargin);
      }

      // Handle edge case where MTM moves a lot and then reserved cash is worth more than MTM.
      // In this case, the original portfolio margin would've been negative, but reserved cash is held by the account.
      // We terminate the auction and allow it to restart in this rare case. In the case MTM < 0, we would start an
      // insolvent auction.
      if (markToMarket >= 0 && int(auctions[accountId].reservedCash) >= markToMarket) {
        return (true, markToMarket, maintenanceMargin, bufferMargin);
      }
      return (bufferMargin >= 0, markToMarket, maintenanceMargin, bufferMargin);
    }
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
   * @notice returns whether an auction is live
   */
  function isAuctionLive(uint accountId) external view returns (bool) {
    return auctions[accountId].ongoing;
  }

  /**
   * @notice External view to get the maximum size of the portfolio that could be bought at the current price
   * @param accountId the id of the account being liquidated
   * @return uint the proportion of the portfolio that could be bought at the current price
   */
  function getMaxProportion(uint accountId, uint scenarioId) external view returns (uint) {
    (, int bufferMargin, int markToMarket) = _getMarginAndMarkToMarket(accountId, scenarioId);

    if (markToMarket < 0) revert DA_SolventAuctionEnded();

    uint discount = _getDiscountPercentage(auctions[accountId].startTime, block.timestamp);

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
      return _getInsolventAuctionBidPrice(accountId, maintenanceMargin, markToMarket);
    }
  }

  function getDiscountPercentage(uint startTime, uint current) external view returns (uint) {
    return _getDiscountPercentage(startTime, current);
  }

  function getMarginAndMarkToMarket(uint accountId, uint scenarioId) external view returns (int mm, int bm, int mtm) {
    return _getMarginAndMarkToMarket(accountId, scenarioId);
  }

  /**
   * @dev return true if the withdraw should be blocked
   */
  function getIsWithdrawBlocked() external view returns (bool) {
    if (totalInsolventMM > 0 && smAccount != 0) {
      int cashBalance = subAccounts.getBalance(smAccount, cash, 0);
      // Note, negative cash balances in sm account will cause reverts
      return totalInsolventMM > cashBalance.toUint256();
    }
    return false;
  }

  function getAuctionParams() external view returns (AuctionParams memory) {
    return auctionParams;
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

    totalInsolventMM -= auction.cachedMM;

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
    view
    returns (uint)
  {
    if (markToMarket < mtmCutoff) {
      return DecimalMath.UNIT;
    }
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
  function _getDiscountPercentage(uint startTimestamp, uint currentTimestamp) internal view returns (uint discount) {
    AuctionParams memory params = auctionParams;

    uint timeElapsed = currentTimestamp - startTimestamp;

    if (timeElapsed < params.fastAuctionLength) {
      // still during the fast auction
      uint totalChangeInFastAuction = params.startingMtMPercentage - params.fastAuctionCutoffPercentage;
      return params.startingMtMPercentage - totalChangeInFastAuction * timeElapsed / params.fastAuctionLength;
    } else if (timeElapsed >= params.fastAuctionLength + params.slowAuctionLength) {
      // whole solvent auction is over
      return 0;
    } else {
      // during the slow auction
      uint timeElapsedInSlow = timeElapsed - params.fastAuctionLength;
      return params.fastAuctionCutoffPercentage
        - uint(params.fastAuctionCutoffPercentage).multiplyDecimal(timeElapsedInSlow).divideDecimal(
          params.slowAuctionLength
        );
    }
  }

  function _getMarginAndMarkToMarket(uint accountId, uint scenarioId)
    internal
    view
    returns (int maintenanceMargin, int bufferMargin, int markToMarket)
  {
    address manager = address(subAccounts.manager(accountId));
    (maintenanceMargin, markToMarket) =
      ILiquidatableManager(manager).getMarginAndMarkToMarket(accountId, false, scenarioId);

    return (maintenanceMargin, _getBufferMargin(maintenanceMargin, markToMarket), markToMarket);
  }

  function _getBufferMargin(int maintenanceMargin, int markToMarket) internal view returns (int) {
    // derive Buffer margin from maintenance margin and mark to market
    int mmBuffer = maintenanceMargin - markToMarket;

    // Buffer margin is a more conservative margin value that we liquidate to, as we do not want users to be flagged
    // multiple times in short order if the price moves against them
    return maintenanceMargin + mmBuffer.multiplyDecimal(auctionParams.bufferMarginPercentage.toInt256());
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
    if (block.timestamp >= auction.startTime + totalLength) return 0;

    if (int(auction.reservedCash) > markToMarket) {
      revert DA_ReservedCashGreaterThanMtM();
    }

    // calculate Bid price using discount and MTM
    uint discount = _getDiscountPercentage(auction.startTime, block.timestamp);

    // Discount the portfolio excluding reserved cash
    return (markToMarket - int(auction.reservedCash)).multiplyDecimal(int(discount));
  }

  /**
   * @dev Return a "negative" bid price. Meaning this is how much the SM is paying the liquidator to take on the risk
   * @dev If MtM is 0, return 0.
   * @return bidPrice a negative number,
   */
  function _getInsolventAuctionBidPrice(uint accountId, int maintenanceMargin, int markToMarket)
    internal
    view
    returns (int)
  {
    if (!auctions[accountId].ongoing) revert DA_AuctionNotStarted();
    if (maintenanceMargin >= 0) return 0;

    // Cap MTM to 0, so it is <= 0.
    markToMarket = SignedMath.min(markToMarket, 0);

    uint timeElapsed = block.timestamp - auctions[accountId].startTime;
    if (timeElapsed >= auctionParams.insolventAuctionLength) {
      return maintenanceMargin;
    } else {
      // linearly growing from mtm to MM, over the length of the auction
      return
        (maintenanceMargin - markToMarket) * int(timeElapsed) / int(auctionParams.insolventAuctionLength) + markToMarket;
    }
  }

  /// @dev Ensure bidder has sufficient cash to pay for the bid
  function _ensureBidderCashBalance(uint bidderId, uint expectedBalance) internal view {
    ISubAccounts.AssetBalance[] memory balances = subAccounts.getAccountBalances(bidderId);
    if (balances.length != 1 || balances[0].asset != cash) revert DA_InvalidBidderPortfolio();
    if (balances[0].balance < expectedBalance.toInt256()) revert DA_InsufficientCash();
  }
}
