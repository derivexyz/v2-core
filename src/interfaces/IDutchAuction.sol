// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IDutchAuction {

  function startAuction(uint accountId) external;

  ////////////
  // EVENTS //
  ////////////

  // emmited when an auction starts
  event AuctionStarted(bytes32 auctionId, uint accountId, uint upperBound, uint lowerBound);

  // emmited when a bid is placed
  event Bid(bytes32 auctionId, address bidder, uint amount);

  // emmited when an auction results in insolvency
  event Insolvent(bytes32 auctionId, uint accountId);

  // emmited when an auction ends, either by insolvency or by the assets of an account being purchased.
  event AuctionEnded(bytes32 auctionId, uint accountId, uint amount);  

  ////////////
  // ERRORS //
  ////////////

  /// @dev emmited when a non-risk manager tries to start an auction
  error DA_NotRiskManager();

  /// @dev emmited when a risk manager tries to start an insolvent auction when bidding
  /// has not concluded.
  error DA_AuctionNotEnteredInsolvency(uint accountId);

  /// @dev emmited when a auction is going to be marked as insolvent with out the auction concluding
  error DA_InsolventNotZero();

  /// @dev emmited when a risk manager tries to start an auction that has already been started
  error DA_AuctionAlreadyStarted(uint accountId);
}
