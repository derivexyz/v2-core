// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title Dutch Auction
 * @author Lyra
 * @notice Auction contract for conducting liquidations of PCRM accounts
 */
interface IDutchAuction {
  function startAuction(uint accountId) external returns (bytes32);
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

  error DA_NotRiskManager();
}
