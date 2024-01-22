// SPDX-License-Identifier: BUSL-1.1

// Config used for integration test, generating integration test anvil state, and more general testing scenarios

pragma solidity ^0.8.0;

import {IDutchAuction} from "../src/interfaces/IDutchAuction.sol";
import {IStandardManager} from "../src/interfaces/IStandardManager.sol";
import {IPMRMLib} from "../src/interfaces/IPMRMLib.sol";
import {IPMRM} from "../src/interfaces/IPMRMLib.sol";


library Config {
    //////////
    // FEES //
    //////////
    uint256 constant public MIN_OI_FEE = 800e18;
    uint256 constant public OI_FEE_BPS = 0.7e18;

    //////////
    // PMRM //
    //////////
    uint constant public MAX_ACCOUNT_SIZE_PMRM = 64;

    function getDefaultScenarios() public  pure returns (IPMRM.Scenario[] memory) {
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

    function getPMRMParams() public pure returns (
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
            pegLossFactor: 2e18,
            confThreshold: 0.6e18,
            confMargin: 0.5e18,
            basePercent: 0.02e18,
            perpPercent: 0.02e18,
            optionPercent: 0.01e18
        });

        marginParams = IPMRMLib.MarginParameters({
            imFactor: 1.3e18,
            baseStaticDiscount: 0.95e18,
            rateMultScale: 4e18,
            rateAddScale: 0.05e18
        });

        volShockParams = IPMRMLib.VolShockParameters({
            volRangeUp: 0.45e18,
            volRangeDown: 0.3e18,
            shortTermPower: 0.3e18,
            longTermPower: 0.13e18,
            dteFloor: 1 days
        });
    }

    /////////
    // SRM //
    /////////

    function getSRMParams() public pure returns (
        IStandardManager.PerpMarginRequirements memory perpMarginRequirements,
        IStandardManager.OptionMarginParams memory optionMarginParams,
        IStandardManager.OracleContingencyParams memory oracleContingencyParams,
        IStandardManager.BaseMarginParams memory baseMarginParams
    ) {
        perpMarginRequirements = IStandardManager.PerpMarginRequirements({
            mmPerpReq: 0.065e18,
            imPerpReq: 0.1e18
        });

        optionMarginParams = IStandardManager.OptionMarginParams({
            maxSpotReq: 0.15e18,
            minSpotReq: 0.1e18,
            mmCallSpotReq: 0.075e18,
            mmPutSpotReq: 0.075e18,
            MMPutMtMReq: 0.075e18,
            unpairedIMScale: 1.2e18,
            unpairedMMScale: 1.1e18,
            mmOffsetScale: 1.05e18
        });

        oracleContingencyParams = IStandardManager.OracleContingencyParams({
            perpThreshold: 0.4e18,
            optionThreshold: 0.4e18,
            baseThreshold: 0.4e18,
            OCFactor: 0.4e18
        });

        baseMarginParams = IStandardManager.BaseMarginParams({
          marginFactor: 0.8e18,
          IMScale: 0.8e18
        });
    }

    //////////////
    // Auctions //
    //////////////

    function getDefaultAuctionParam() public pure returns (IDutchAuction.AuctionParams memory param) {
        param = IDutchAuction.AuctionParams({
          startingMtMPercentage: 1e18,
          fastAuctionCutoffPercentage: 0.8e18,
          fastAuctionLength: 10 minutes,
          slowAuctionLength: 2 hours,
          insolventAuctionLength: 10 minutes,
          liquidatorFeeRate: 0.05e18,
          bufferMarginPercentage: 0.3e18
        });
    }

}