// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title Dutch Auction
 * @author Lyra
 * @notice Auction contract for conducting liquidations of PCRM accounts
 */
interface IDutchAuction {
  function startAuction(uint accountId) external;
  ////////////
  // EVENTS //
  ////////////

  // emmited when an auction starts
  event AuctionStarted(uint accountId, int upperBound, int lowerBound, uint startTime);

  // emmited when a bid is placed
  event Bid(uint accountId, uint bidderId, uint amount);

  // emmited when an auction results in insolvency
  event Insolvent(uint accountId);

  // emmited when an auction ends, either by insolvency or by the assets of an account being purchased.
  event AuctionEnded(uint accountId, uint amount);

  ////////////
  // ERRORS //
  ////////////

  /// @dev emmited when a non-risk manager tries to start an auction
  error DA_NotRiskManager();

  /// @dev emmited when a risk manager tries to start an insolvent auction when bidding
  /// has not concluded.
  error DA_AuctionNotEnteredInsolvency(uint accountId);

  /// @dev emmited when a risk manager tries to start an auction that has already been started
  error DA_AuctionAlreadyStarted(uint accountId);

  /// @dev emmited when a bid is submitted on a closed/ended auction
  error DA_AuctionEnded(uint accountId);

  /// @dev emmmited when an auction is settled
  error DA_AuctionNotOngoing(uint accountId);

  /// @dev emitted when a bid is submitted where percentage > 100% of portfolio
  error DA_AmountTooLarge(uint accountId, uint amount);

  /// @dev emitted when a bid is submitted for 0% of the portfolio
  error DA_AmountInvalid(uint accountId, uint amount);

  /// @dev emitted when a user tries to increment the step for an insovlent auction
  error DA_AuctionNotInsolventCannotStep(uint accountId);

  /// @dev emitted when a user doesn't own the account that they are trying to bid on
  error DA_BidderNotOwner(uint accountId, address bidder);
}
