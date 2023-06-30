// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IDutchAuction} from "../src/interfaces/IDutchAuction.sol";
import {IStandardManager} from "../src/interfaces/IStandardManager.sol";

/**
 * @dev default interest rate params for interest rate model
 */
function getDefaultInterestRateModel() pure returns (
  uint minRate, 
  uint rateMultiplier, 
  uint highRateMultiplier, 
  uint optimalUtil
) {
  minRate = 0.06 * 1e18;
  rateMultiplier = 0.2 * 1e18;
  highRateMultiplier = 0.4 * 1e18;
  optimalUtil = 0.6 * 1e18;
}

function getDefaultAuctionParam() pure returns (IDutchAuction.SolventAuctionParams memory param) {
  param = IDutchAuction.SolventAuctionParams({
    startingMtMPercentage: 1e18,
    fastAuctionCutoffPercentage: 0.8e18,
    fastAuctionLength: 10 minutes,
    slowAuctionLength: 2 hours,
    liquidatorFeeRate: 0.05e18
  });
}

function getDefaultInsolventAuctionParam() pure returns (IDutchAuction.InsolventAuctionParams memory param) {
  param = IDutchAuction.InsolventAuctionParams({totalSteps: 100, coolDown: 5 seconds, bufferMarginScalar: 1.2e18});
}

function getDefaultDepegParam() pure returns (IStandardManager.DepegParams memory param) {
  param = IStandardManager.DepegParams({threshold: 0.98e18, depegFactor: 1.2e18});
}

int constant MAX_Abs_Rate_Per_Hour = 0.1e18;

uint64 constant SPOT_HEARTBEAT = 10 minutes;
uint64 constant FORWARD_HEARTBEAT = 10 minutes;
uint64 constant SETTLEMENT_HEARTBEAT = 1 hours;

uint64 constant PERP_HEARTBEAT = 10 minutes;
uint64 constant IMPACT_PRICE_HEARTBEAT = 20 minutes;

uint64 constant VOL_HEARTBEAT = 20 minutes;
uint64 constant RATE_HEARTBEAT = 7 days;
