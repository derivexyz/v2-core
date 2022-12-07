// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/token/ERC721/ERC721.sol";
import "openzeppelin/utils/math/SafeCast.sol";

import "../../interfaces/LiquidationStructs.sol";

/**
 * @title PCRMLiquidation
 * @author Lyra
 * @notice Liquidation module for PCRM (Partial Collateral Risk Manager). In charge of:
 *         1. start an auction for a underwater account
 *         2. determine what part of the portfolio should be put on liquidation
 */
contract PCRMLiquidation {
  ////////////////////
  //    Variables   //
  ////////////////////

  ///@dev auction id to auction detail
  mapping(uint => AuctionDetail) auctions;

  ///@dev length of auction in seconds
  uint64 auctionLength;

  /////////////////////////////
  //    External Functions   //
  /////////////////////////////

  /**
   * @notice
   * @dev
   * @param accountId account to be flagged
   */
  function flagLiquidation(uint accountId) external {
    // check that account is underwater

    // request the manager to transfer the account ownership to the liquidation module

    // start an auction

    // incentive to caller?
  }

  /**
   * @notice participate in the auction to liquidate an account
   * @dev the caller need to grant access to ths contrat to move its balance in Account
   * @param auctionId auction id
   * @param fromAccount account to receive debt and cash
   * @param amountPercentage amount to liquidate
   * @param minUsdc min amount to receive
   */
  function liquidate(uint auctionId, uint fromAccount, uint amountPercentage, uint minUsdc) external {
    // check fromAccount access

    // check auction state

    // caculate curr price based on timestamp

    // calculate f base on portfolio and price

    // trigger transfer on Account (need funds from security module if auctioning account is far underwater)

    // if the auction ends, transfer the account back to original owner

    // update auction id state
  }

  ////////////////////
  //    Internal    //
  ////////////////////

  /**
   * @dev description: price calculation
   * @param accountId account id
   */
  function _startAuction(uint accountId) internal returns (uint auctionId) {
    // get the account detail

    // calculate init price to sell the portfolio (intrinsic value of all long and short)

    // calculate end price to sell the portfolio (assuming worst case: 300 vol for short & 0 for long)

    // update auction id

    // emit event
  }
}
