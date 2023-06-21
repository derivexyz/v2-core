// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface IDutchAuction {
  struct Auction {
    /// the accountId that is being liquidated
    uint accountId;
    /// scenario ID used to calculate IM or MtM. Ignored for Basic Manager
    uint scenarioId;
    /// Boolean that will be switched when the auction price passes through 0
    bool insolvent;
    /// If an auction is active
    bool ongoing;
    /// The percentage of the portfolio that is left to be auctioned
    uint percentageLeft;
    /// The startTime of the auction
    uint startTime;
    /// The total amount of cash paid into the account during the auction
    uint reservedCash;
    /// Is this a forced liquidation
    bool isForce;
    /*------------------------- *
     * Insolvent Auction Params *
    /*------------------------- */
    /// The change in value of the portfolio per step in dollars when not insolvent
    uint stepSize;
    /// The current step if the auction is insolvent
    uint stepInsolvent;
    /// The timestamp of the last increase of steps for insolvent auction
    uint lastStepUpdate;
    /// If this auction is blocking cash withdraw
    bool isBlockingWithdraw;
  }

  struct SolventAuctionParams {
    /// Starting percentage of MtM. 1e18 is 100%
    uint64 startingMtMPercentage;
    /// Percentage that starts the slow auction
    uint64 fastAuctionCutoffPercentage;
    /// Fast auction length in seconds
    uint32 fastAuctionLength;
    /// Slow auction length in seconds
    uint32 slowAuctionLength;
    // Liquidator fee rate in percentage, 1e18 = 100%
    uint64 liquidatorFeeRate;
  }

  struct InsolventAuctionParams {
    /// total seconds
    uint32 totalSteps;
    // Amount of seconds to go to next step
    uint32 coolDown;
    /// buffer margin scalar. liquidation will go from 0 to (buffer margin) * scalar
    int64 bufferMarginScalar;
  }

  function startAuction(uint accountId, uint scenarioId) external;

  function startForcedAuction(uint accountId, uint scenarioId) external;

  function getIsWithdrawBlocked() external view returns (bool);

  ////////////
  // EVENTS //
  ////////////

  // emitted when a solvent auction starts
  event SolventAuctionStarted(uint accountId, uint scenarioId, int markToMarket, uint fee);

  // emitted when an insolvent auction starts
  event InsolventAuctionStarted(uint accountId, uint steps, uint stepSize);

  // emitted when a bid is placed
  event Bid(uint accountId, uint bidderId, uint finalPercentage, uint cashFromBidder, uint cashToBidder);

  // emitted when an auction ends, either by insolvency or by the assets of an account being purchased.
  event AuctionEnded(uint accountId, uint endTime);

  event InsolventAuctionStepIncremented(uint accountId, uint newStep);

  event ScenarioIdUpdated(uint accountId, uint newScenarioId);

  ////////////
  // ERRORS //
  ////////////

  /// @dev emitted owner is trying to set a bad parameter for auction
  error DA_InvalidParameter();

  /// @dev emitted owner is trying to set bad threshold that could block cash withdraw
  error DA_InvalidWithdrawBlockThreshold();

  /// @dev Cannot stop an ongoing auction
  error DA_NotOngoingAuction();

  /// @dev emitted when someone tries to start an insolvent auction when bidding
  /// has not concluded.
  error DA_OngoingSolventAuction();

  /// @dev revert if trying to start an auction when it's above maintenance margin (well collateralized)
  error DA_AccountIsAboveMaintenanceMargin();

  /// @dev emitted when someone tries mark an insolvent auction again
  error DA_AuctionAlreadyInInsolvencyMode();

  /// @dev emitted when someone tries to bid on auction that has not started
  error DA_AuctionNotStarted();

  /// @dev emitted when a risk manager tries to start an auction that has already been started
  error DA_AuctionAlreadyStarted();

  /// @dev emitted when a bid is submitted on a solvent auction that has passed the auction time
  ///      at this point, it can be converted into insolvent auction and keep going.
  error DA_SolventAuctionEnded();

  /// @dev emitted when a bid is submitted where percentage > 100% of portfolio
  error DA_InvalidPercentage();

  /// @dev emitted when a bid is submitted for 0% of the portfolio
  error DA_AmountIsZero();

  /// @dev emitted when owner trying to set a invalid buffer margin param
  error DA_InvalidBufferMarginParameter();

  /// @dev emitted when a user tries to increment the step for an insolvent auction
  error DA_SolventAuctionCannotIncrement();

  /// @dev emitted when a user doesn't own the account that they are trying to bid from
  error DA_SenderNotOwner();

  /// @dev emitted when a user tries to terminate an auction but the account is still underwater
  error DA_AuctionCannotTerminate();

  /// @dev can only specify an id that make the IM worse
  error DA_ScenarioIdNotWorse();

  /// @dev emitted when a user tries to bid on an auction, but it should be terminated
  error DA_AuctionShouldBeTerminated();

  /// @dev emitted when a increase the step for an insolvent auction that has already reach its steps
  error DA_MaxStepReachedInsolventAuction();

  /// @dev emitted when IncrementInsolventAuction is spammed
  error DA_InCoolDown();

  /// @dev emitted when reserved cash exceeds MTM. Auction should be terminated and restarted.
  error DA_ReservedCashGreaterThanMtM();

  /// @dev emitted when trying to continue a forced auction when MM > 0.
  error DA_CannotStepSolventForcedAuction();

  /// @dev emitted when calling force liquidate not from the account's manager.
  error DA_OnlyManager();
}
