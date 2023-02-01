// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IDutchAuction {
  function startAuction(uint accountId) external;

  ////////////
  // EVENTS //
  ////////////

  // emitted when an auction starts
  event AuctionStarted(uint accountId, int upperBound, int lowerBound, uint startTime, bool insolvent);

  // emitted when a bid is placed
  event Bid(uint accountId, uint bidderId, uint percentagePortfolio, uint cash, uint fee);

  // emitted when an auction results in insolvency
  event Insolvent(uint accountId);

  // emitted when an auction ends, either by insolvency or by the assets of an account being purchased.
  event AuctionEnded(uint accountId, uint endTime);

  ////////////
  // ERRORS //
  ////////////

  /// @dev emitted when a non-risk manager tries to start an auction
  error DA_NotRiskManager();

  /// @dev emitted owner is trying to set a bad parameter for auction
  error DA_InvalidParameter();

  /// @dev emitted when someone tries to start an insolvent auction when bidding
  /// has not concluded.
  error DA_AuctionNotEnteredInsolvency(uint accountId);

  /// @dev emitted when someone tries mark an insolvent auction again
  error DA_AuctionAlreadyInInsolvencyMode(uint accountId);

  /// @dev emitted when someone tries to start an auction that has already been started
  error DA_AuctionNotStarted(uint accountId);

  /// @dev emitted when a risk manager tries to start an auction that has already been started
  error DA_AuctionAlreadyStarted(uint accountId);

  /// @dev emitted when a bid is submitted on a solvent auction that has passed the auction time
  ///      at this point, it can be converted into insolvent auction and keep going.
  error DA_SolventAuctionEnded();

  /// @dev emitted when a bid is submitted where percentage > 100% of portfolio
  error DA_AmountTooLarge(uint accountId, uint amount);

  /// @dev emitted when a bid is submitted for 0% of the portfolio
  error DA_AmountIsZero(uint accountId);

  /// @dev emitted when a user tries to increment the step for an insolvent auction
  error DA_SolventAuctionCannotIncrement(uint accountId);

  /// @dev emitted when a user doesn't own the account that they are trying to bid on
  error DA_BidderNotOwner(uint accountId, address bidder);

  /// @dev emitted when a user tries to terminate an insolvent Auction
  error DA_AuctionCannotTerminate(uint accountId);

  /// @dev emitted when a increase the step for an insolvent auction that has already reach its steps
  error DA_MaxStepReachedInsolventAuction();

  /// @dev emitted when IncrementInsolventAuction is spammed
  error DA_CannotStepBeforeCoolDownEnds(uint blockTimeStamp, uint coolDownEnds);
}
