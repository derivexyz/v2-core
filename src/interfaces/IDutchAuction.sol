// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title Dutch Auction 
 * @author Lyra
 * @notice Auction contract for conducting liquidations of PCRM accounts
 */

interface IDutchAuction {
  function startAuction(uint accountId) external;
}
