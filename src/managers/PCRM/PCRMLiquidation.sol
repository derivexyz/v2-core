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

  function flagLiquidation(uint accountId) external {
    // check that account is underwater

    // request the manager to transfer the account ownership to the liquidation module

    // start an auction
  }

  /**
   * @notice participate in the auction and liquidate an account
   */
  function liquidate(uint auctionId, uint fromAccount, uint amountPercentage, uint maxUsdc) external {
    // check fromAccount access

    // check auction state

    // caculate price based on timestamp

    // calculate f base on portfolio and price

    // trigger transfer on Account

    // if the auction ends, transfer the account back to original owner
  }

  /**
   * @notice if the auction time has passed and no one is willing to take the portfolio
   *         anyone can use this function to trigger the bail out pool to take the position.
   */
  function bailOutPorfolio(uint auctionid) external {
    // check auction state

    // tansfer whole account to the bail out pool
  }

  ////////////////////
  //    Internal    //
  ////////////////////

  function _startAuction(uint accountId) internal returns (uint auctionId) {
    // get the account

    // calculate init price to sell the portfolio (intrinsic value of all long and short)

    // update auction id

    // emit event
  }
}
