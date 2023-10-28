// SPDX-License-Identifier: MIT

// Config used for integration test, generating integration test anvil state, and more general testing scenarios

pragma solidity ^0.8.0;

import {IDutchAuction} from "../src/interfaces/IDutchAuction.sol";
import {IStandardManager} from "../src/interfaces/IStandardManager.sol";
import {IPMRMLib} from "../src/interfaces/IPMRMLib.sol";
import {IPMRM} from "../src/interfaces/IPMRMLib.sol";

/**
 * @dev default interest rate params for interest rate model
 */
function getDefaultInterestRateModel() pure returns (
  uint minRate, 
  uint rateMultiplier, 
  uint highRateMultiplier, 
  uint optimalUtil
) {
  minRate = 0.04e18;
  rateMultiplier = 0.1e18;
  highRateMultiplier = 1.25e18;
  optimalUtil = 0.7e18;
}

// Liquidations

int constant BUFFER_MARGIN_SCALE = 0.3e18;

function getDefaultAuctionParam() pure returns (IDutchAuction.AuctionParams memory param) {
  param = IDutchAuction.AuctionParams({
    startingMtMPercentage: 0.95e18,
    fastAuctionCutoffPercentage: 0.7e18,
    fastAuctionLength: 20 minutes,
    slowAuctionLength: 3 hours,
    insolventAuctionLength: 10 minutes,
    liquidatorFeeRate: 0
  });
}

function getDefaultDepegParam() pure returns (IStandardManager.DepegParams memory param) {
  param = IStandardManager.DepegParams({threshold: 0.98e18, depegFactor: 1.2e18});
}

// Cash Asset
uint256 constant CASH_SM_FEE=0.2e18;

// Assets

int constant MAX_Abs_Rate_Per_Hour = 0.1e18;

uint256 constant MIN_OI_FEE = 2e18;
uint256 constant OI_FEE_BPS = 0.001e18;

uint256 constant SRM_BASE_DISCOUNT = 0.75e18;
uint256 constant SRM_IM_BASE_DISCOUNT = 0.8e18;

// Feeds

uint64 constant SPOT_HEARTBEAT = 10 minutes;
uint64 constant FORWARD_HEARTBEAT = 10 minutes;
uint64 constant SETTLEMENT_HEARTBEAT = 1 hours;

uint64 constant PERP_HEARTBEAT = 10 minutes;
uint64 constant IMPACT_PRICE_HEARTBEAT = 20 minutes;

uint64 constant VOL_HEARTBEAT = 20 minutes;
uint64 constant RATE_HEARTBEAT = 7 days;

uint constant INIT_CAP_PERP = 100_000e18;
uint constant INIT_CAP_OPTION = 1000_000e18;
uint constant INIT_CAP_BASE = 1_000e18;

// ========== Standard Manager Params =========== //

function getDefaultSRMOptionParam() pure returns (IStandardManager.OptionMarginParams memory param) {
  param =IStandardManager.OptionMarginParams({
      maxSpotReq: 0.15e18,
      minSpotReq: 0.12e18,
      mmCallSpotReq: 0.1e18,
      mmPutSpotReq: 0.1e18,
      MMPutMtMReq: 0.1e18,
      unpairedIMScale: 1.2e18,
      unpairedMMScale: 1.1e18,
      mmOffsetScale: 1.05e18
    });
}

function getDefaultSRMOracleContingency() pure returns (IStandardManager.OracleContingencyParams memory param) {
  param = IStandardManager.OracleContingencyParams(0.4e18, 0.4e18, 0.4e18, 0.4e18);
}

function getDefaultSRMPerpRequirements() pure returns (uint mmRequirement, uint imRequirement) {
  mmRequirement = 0.05e18;
  imRequirement = 0.065e18;
}

// ========== Portfolio Margin Manager Params =========== //

function getPMRMParams() pure returns (
  IPMRMLib.BasisContingencyParameters memory basisContParams,
  IPMRMLib.OtherContingencyParameters memory otherContParams,
  IPMRMLib.MarginParameters memory marginParams,
  IPMRMLib.VolShockParameters memory volShockParams
) {
  basisContParams = IPMRMLib.BasisContingencyParameters({
        scenarioSpotUp: 1.05e18,
        scenarioSpotDown: 0.95e18,
        basisContAddFactor: 0.25e18,
        basisContMultFactor: 0.01e18
      });

  otherContParams = IPMRMLib.OtherContingencyParameters({
    pegLossThreshold: 0.98e18,
    pegLossFactor: 4e18,
    confThreshold: 0.6e18,
    confMargin: 0.5e18,
    basePercent: 0.025e18,
    perpPercent: 0.025e18,
    optionPercent: 0.01e18
  });

  marginParams = IPMRMLib.MarginParameters({
    imFactor: 1.3e18,
    baseStaticDiscount: 0.95e18,
    rateMultScale: 2e18,
    rateAddScale: 0.12e18
  });

  volShockParams = IPMRMLib.VolShockParameters({
    volRangeUp: 0.45e18,
    volRangeDown: 0.3e18,
    shortTermPower: 0.3e18,
    longTermPower: 0.13e18,
    dteFloor: 1 days
  });
}

function getDefaultScenarios() pure returns (IPMRM.Scenario[] memory) {
  IPMRM.Scenario[] memory scenarios = new IPMRM.Scenario[](21);

  scenarios[0] = IPMRM.Scenario({spotShock: 1.15e18, volShock: IPMRM.VolShockDirection.Up});
  scenarios[1] = IPMRM.Scenario({spotShock: 1.15e18, volShock: IPMRM.VolShockDirection.None});
  scenarios[2] = IPMRM.Scenario({spotShock: 1.15e18, volShock: IPMRM.VolShockDirection.Down});
  scenarios[3] = IPMRM.Scenario({spotShock: 1.1e18, volShock: IPMRM.VolShockDirection.Up});
  scenarios[4] = IPMRM.Scenario({spotShock: 1.1e18, volShock: IPMRM.VolShockDirection.None});
  scenarios[5] = IPMRM.Scenario({spotShock: 1.1e18, volShock: IPMRM.VolShockDirection.Down});
  scenarios[6] = IPMRM.Scenario({spotShock: 1.05e18, volShock: IPMRM.VolShockDirection.Up});
  scenarios[7] = IPMRM.Scenario({spotShock: 1.05e18, volShock: IPMRM.VolShockDirection.None});
  scenarios[8] = IPMRM.Scenario({spotShock: 1.05e18, volShock: IPMRM.VolShockDirection.Down});
  scenarios[9] = IPMRM.Scenario({spotShock: 1e18, volShock: IPMRM.VolShockDirection.Up});
  scenarios[10] = IPMRM.Scenario({spotShock: 1e18, volShock: IPMRM.VolShockDirection.None});
  scenarios[11] = IPMRM.Scenario({spotShock: 1e18, volShock: IPMRM.VolShockDirection.Down});
  scenarios[12] = IPMRM.Scenario({spotShock: 0.95e18, volShock: IPMRM.VolShockDirection.Up});
  scenarios[13] = IPMRM.Scenario({spotShock: 0.95e18, volShock: IPMRM.VolShockDirection.None});
  scenarios[14] = IPMRM.Scenario({spotShock: 0.95e18, volShock: IPMRM.VolShockDirection.Down});
  scenarios[15] = IPMRM.Scenario({spotShock: 0.9e18, volShock: IPMRM.VolShockDirection.Up});
  scenarios[16] = IPMRM.Scenario({spotShock: 0.9e18, volShock: IPMRM.VolShockDirection.None});
  scenarios[17] = IPMRM.Scenario({spotShock: 0.9e18, volShock: IPMRM.VolShockDirection.Down});
  scenarios[18] = IPMRM.Scenario({spotShock: 0.85e18, volShock: IPMRM.VolShockDirection.Up});
  scenarios[19] = IPMRM.Scenario({spotShock: 0.85e18, volShock: IPMRM.VolShockDirection.None});
  scenarios[20] = IPMRM.Scenario({spotShock: 0.85e18, volShock: IPMRM.VolShockDirection.Down});

  return scenarios;
}
