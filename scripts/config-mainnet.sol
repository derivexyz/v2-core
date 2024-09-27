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
    uint256 constant public MIN_OI_FEE = 50e18;
    uint256 constant public OI_FEE_BPS = 0.1e18;

    //////////
    // PMRM //
    //////////
    uint constant public MAX_ACCOUNT_SIZE_PMRM = 128;

    function getDefaultScenarios() public  pure returns (IPMRM.Scenario[] memory) {
        IPMRM.Scenario[] memory scenarios = new IPMRM.Scenario[](23);
        scenarios[0] = IPMRM.Scenario({spotShock: 1.20e18, volShock: IPMRM.VolShockDirection.Up});
        scenarios[1] = IPMRM.Scenario({spotShock: 1.15e18, volShock: IPMRM.VolShockDirection.Up});
        scenarios[2] = IPMRM.Scenario({spotShock: 1.15e18, volShock: IPMRM.VolShockDirection.None});
        scenarios[3] = IPMRM.Scenario({spotShock: 1.15e18, volShock: IPMRM.VolShockDirection.Down});
        scenarios[4] = IPMRM.Scenario({spotShock: 1.10e18, volShock: IPMRM.VolShockDirection.Up});
        scenarios[5] = IPMRM.Scenario({spotShock: 1.10e18, volShock: IPMRM.VolShockDirection.None});
        scenarios[6] = IPMRM.Scenario({spotShock: 1.10e18, volShock: IPMRM.VolShockDirection.Down});
        scenarios[7] = IPMRM.Scenario({spotShock: 1.05e18, volShock: IPMRM.VolShockDirection.Up});
        scenarios[8] = IPMRM.Scenario({spotShock: 1.05e18, volShock: IPMRM.VolShockDirection.None});
        scenarios[9] = IPMRM.Scenario({spotShock: 1.05e18, volShock: IPMRM.VolShockDirection.Down});
        scenarios[10] = IPMRM.Scenario({spotShock: 1e18, volShock: IPMRM.VolShockDirection.Up});
        scenarios[11] = IPMRM.Scenario({spotShock: 1e18, volShock: IPMRM.VolShockDirection.None});
        scenarios[12] = IPMRM.Scenario({spotShock: 1e18, volShock: IPMRM.VolShockDirection.Down});
        scenarios[13] = IPMRM.Scenario({spotShock: 0.95e18, volShock: IPMRM.VolShockDirection.Up});
        scenarios[14] = IPMRM.Scenario({spotShock: 0.95e18, volShock: IPMRM.VolShockDirection.None});
        scenarios[15] = IPMRM.Scenario({spotShock: 0.95e18, volShock: IPMRM.VolShockDirection.Down});
        scenarios[16] = IPMRM.Scenario({spotShock: 0.90e18, volShock: IPMRM.VolShockDirection.Up});
        scenarios[17] = IPMRM.Scenario({spotShock: 0.90e18, volShock: IPMRM.VolShockDirection.None});
        scenarios[18] = IPMRM.Scenario({spotShock: 0.90e18, volShock: IPMRM.VolShockDirection.Down});
        scenarios[19] = IPMRM.Scenario({spotShock: 0.85e18, volShock: IPMRM.VolShockDirection.Up});
        scenarios[20] = IPMRM.Scenario({spotShock: 0.85e18, volShock: IPMRM.VolShockDirection.None});
        scenarios[21] = IPMRM.Scenario({spotShock: 0.85e18, volShock: IPMRM.VolShockDirection.Down});
        scenarios[22] = IPMRM.Scenario({spotShock: 0.80e18, volShock: IPMRM.VolShockDirection.Up});
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
            basisContAddFactor: 1.0e18,
            basisContMultFactor: 1.2e18
        });

        otherContParams = IPMRMLib.OtherContingencyParameters({
            pegLossThreshold: 0.99e18,
            pegLossFactor: 4e18,
            confThreshold: 0.55e18,
            confMargin: 1e18,
            basePercent: 0.03e18,
            perpPercent: 0.03e18,
            optionPercent: 0.02e18
        });

        marginParams = IPMRMLib.MarginParameters({
            imFactor: 1.25e18,
            baseStaticDiscount: 0.95e18,
            rateMultScale: 1e18,
            rateAddScale: 0.12e18
        });

        volShockParams = IPMRMLib.VolShockParameters({
            volRangeUp: 0.6e18,
            volRangeDown: 0.3e18,
            shortTermPower: 0.3e18,
            longTermPower: 0.13e18,
            dteFloor: 1 days
        });
    }

    function getPMRMCaps(string memory market) public pure returns (uint perpCap, uint optionCap, uint baseCap) {
        if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("ETH"))) {
            perpCap = 250_000e18;
            optionCap = 2_000_000e18;
            baseCap = 750e18;
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("BTC"))) {
            perpCap = 12_000e18;
            optionCap = 100_000e18;
            baseCap = 15e18;
        } else {
            revert("market not supported");
        }
    }

    /////////
    // SRM //
    /////////

    // The reason that this is not the same size as PMRM is because we don't expect SRM users to have as many positions as PMRM users
    // so to reduce risk latency for latency-sensitive PMRM users, we are keeping the size of the SRM users smaller for now.
    uint public constant MAX_ACCOUNT_SIZE_SRM = 48;
    bool public constant BORROW_ENABLED = true;

    function getSRMDepegParams() public pure returns (
        IStandardManager.DepegParams memory depegParams
    ) {
        depegParams = IStandardManager.DepegParams({
            threshold: 0.99e18,
            depegFactor: 2e18
        });
    }

    function getSRMParams(string memory market) public pure returns (
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
            minSpotReq: 0.13e18,
            mmCallSpotReq: 0.09e18,
            mmPutSpotReq: 0.09e18,
            MMPutMtMReq: 0.09e18,
            unpairedIMScale: 1.2e18,
            unpairedMMScale: 1.1e18,
            mmOffsetScale: 1.05e18
        });

        oracleContingencyParams = IStandardManager.OracleContingencyParams({
            perpThreshold: 0.55e18,
            optionThreshold: 0.55e18,
            baseThreshold: 0.55e18,
            OCFactor: 1e18
        });

        if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("ETH"))) {
            baseMarginParams = IStandardManager.BaseMarginParams({
                marginFactor: 0.8e18,
                IMScale: 0.9375e18
            });
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("BTC"))) {
            baseMarginParams = IStandardManager.BaseMarginParams({
                marginFactor: 0.75e18,
                IMScale: 0.93e18
            });
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("USDT"))) {
            baseMarginParams = IStandardManager.BaseMarginParams({
                marginFactor: 0.98e18,
                IMScale: 0.98e18
            });
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("WSTETH"))) {
            baseMarginParams = IStandardManager.BaseMarginParams({
                marginFactor: 0.8e18,
                IMScale: 0.9375e18
            });
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("SFP"))) {
            baseMarginParams = IStandardManager.BaseMarginParams({
                marginFactor: 0.98e18,
                IMScale: 0.98e18
            });
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("SNX"))) {
            baseMarginParams = IStandardManager.BaseMarginParams({
                marginFactor: 0.7e18,
                IMScale: 0.65e18
            });

            optionMarginParams = IStandardManager.OptionMarginParams({
                maxSpotReq: 0.25e18,
                minSpotReq: 0.225e18,
                mmCallSpotReq: 0.15e18,
                mmPutSpotReq: 0.15e18,
                MMPutMtMReq: 0.15e18,
                unpairedIMScale: 1.4e18,
                unpairedMMScale: 1.3e18,
                mmOffsetScale: 1.05e18
            });
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("SOL"))) {
            perpMarginRequirements = IStandardManager.PerpMarginRequirements({
                mmPerpReq: 0.1e18,
                imPerpReq: 0.2e18
            });
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("DOGE"))) {
            perpMarginRequirements = IStandardManager.PerpMarginRequirements({
                mmPerpReq: 0.1e18,
                imPerpReq: 0.2e18
            });
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("rswETH"))) {
            baseMarginParams = IStandardManager.BaseMarginParams({
                marginFactor: 0.65e18,
                IMScale: 0.77e18
            });
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("rsETH"))) {
            baseMarginParams = IStandardManager.BaseMarginParams({
                marginFactor: 0.65e18,
                IMScale: 0.77e18
            });
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("weETH"))) {
            baseMarginParams = IStandardManager.BaseMarginParams({
                marginFactor: 0.65e18,
                IMScale: 0.77e18
            });
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("DAI"))) {
            baseMarginParams = IStandardManager.BaseMarginParams({
                marginFactor: 0.925e18,
                IMScale: 0.92e18
            });
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("sDAI"))) {
            baseMarginParams = IStandardManager.BaseMarginParams({
                marginFactor: 0.875e18,
                IMScale: 0.915e18
            });
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("USDe"))) {
            baseMarginParams = IStandardManager.BaseMarginParams({
                marginFactor: 0.8e18,
                IMScale: 0.875e18
            });
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("PYUSD"))) {
            baseMarginParams = IStandardManager.BaseMarginParams({
                marginFactor: 0.925e18,
                IMScale: 0.92e18
            });
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("LBTC"))) {
            baseMarginParams = IStandardManager.BaseMarginParams({
                marginFactor: 0.65e18,
                IMScale: 0.77e18
            });
        }  else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("cbBTC"))) {
            baseMarginParams = IStandardManager.BaseMarginParams({
                marginFactor: 0.65e18,
                IMScale: 0.77e18
            });
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("eBTC"))) {
            baseMarginParams = IStandardManager.BaseMarginParams({
                marginFactor: 0.65e18,
                IMScale: 0.77e18
            });
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("TIA"))) {
            perpMarginRequirements = IStandardManager.PerpMarginRequirements({
                mmPerpReq: 0.1e18,
                imPerpReq: 0.2e18
            });
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("SUI"))) {
            perpMarginRequirements = IStandardManager.PerpMarginRequirements({
                mmPerpReq: 0.1e18,
                imPerpReq: 0.2e18
            });
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("NEAR"))) {
            perpMarginRequirements = IStandardManager.PerpMarginRequirements({
                mmPerpReq: 0.1e18,
                imPerpReq: 0.2e18
            });
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("PEPE"))) {
            perpMarginRequirements = IStandardManager.PerpMarginRequirements({
                mmPerpReq: 0.1e18,
                imPerpReq: 0.2e18
            });
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("WIF"))) {
            perpMarginRequirements = IStandardManager.PerpMarginRequirements({
                mmPerpReq: 0.1e18,
                imPerpReq: 0.2e18
            });
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("WLD"))) {
            perpMarginRequirements = IStandardManager.PerpMarginRequirements({
                mmPerpReq: 0.1e18,
                imPerpReq: 0.2e18
            });
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("BNB"))) {
            perpMarginRequirements = IStandardManager.PerpMarginRequirements({
                mmPerpReq: 0.1e18,
                imPerpReq: 0.2e18
            });
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("AAVE"))) {
            perpMarginRequirements = IStandardManager.PerpMarginRequirements({
                mmPerpReq: 0.1e18,
                imPerpReq: 0.2e18
            });
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("OP"))) {
            perpMarginRequirements = IStandardManager.PerpMarginRequirements({
                mmPerpReq: 0.1e18,
                imPerpReq: 0.2e18
            });
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("ARB"))) {
            perpMarginRequirements = IStandardManager.PerpMarginRequirements({
                mmPerpReq: 0.1e18,
                imPerpReq: 0.2e18
            });
        } else {
            revert("market not supported");
        }
    }

    function getSRMCaps(string memory market) public pure returns (uint perpCap, uint optionCap, uint baseCap) {
        if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("ETH"))) {
            perpCap = 250_000e18;
            optionCap = 2_000_000e18;
            baseCap = 250e18;
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("BTC"))) {
            perpCap = 12_000e18;
            optionCap = 100_000e18;
            baseCap = 5e18;
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("USDT"))) {
            perpCap = 0;
            optionCap = 0;
            baseCap = 100_000e18;
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("WSTETH"))) {
            perpCap = 0;
            optionCap = 0;
            baseCap = 500e18;
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("SFP"))) {
            perpCap = 0;
            optionCap = 0;
            baseCap = 250000e18;
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("SNX"))) {
            perpCap = 0;
            optionCap = 30_000e18;
            baseCap = 30_000e18;
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("SOL"))) {
            perpCap = 1_000_000e18;
            optionCap = 0;
            baseCap = 0;
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("DOGE"))) {
            perpCap = 10_000_000e18;
            optionCap = 0;
            baseCap = 0;
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("rswETH"))) {
            perpCap = 0;
            optionCap = 0;
            baseCap = 10_000_000e18;
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("rsETH"))) {
            perpCap = 0;
            optionCap = 0;
            baseCap = 10_000_000e18;
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("weETH"))) {
            perpCap = 0;
            optionCap = 0;
            baseCap = 10_000_000e18;
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("DAI"))) {
            perpCap = 0;
            optionCap = 0;
            baseCap = 3_000_000e18;
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("sDAI"))) {
            perpCap = 0;
            optionCap = 0;
            baseCap = 3_000_000e18;
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("USDe"))) {
            perpCap = 0;
            optionCap = 0;
            baseCap = 500_000e18;
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("PYUSD"))) {
            perpCap = 0;
            optionCap = 0;
            baseCap = 1_000_000e18;
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("LBTC"))) {
            perpCap = 0;
            optionCap = 0;
            baseCap = 10_000_000e18;
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("cbBTC"))) {
            perpCap = 0;
            optionCap = 0;
            baseCap = 10_000_000e18;
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("eBTC"))) {
            perpCap = 0;
            optionCap = 0;
            baseCap = 10_000_000e18;
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("TIA"))) {
            perpCap = 10_000_000e18;
            optionCap = 0;
            baseCap = 0;
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("SUI"))) {
            perpCap = 10_000_000e18;
            optionCap = 0;
            baseCap = 0;
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("NEAR"))) {
            perpCap = 10_000_000e18;
            optionCap = 0;
            baseCap = 0;
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("PEPE"))) {
            perpCap = 10_000_000e18;
            optionCap = 0;
            baseCap = 0;
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("WIF"))) {
            perpCap = 10_000_000e18;
            optionCap = 0;
            baseCap = 0;
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("WLD"))) {
            perpCap = 10_000_000e18;
            optionCap = 0;
            baseCap = 0;
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("BNB"))) {
            perpCap = 10_000_000e18;
            optionCap = 0;
            baseCap = 0;
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("AAVE"))) {
            perpCap = 10_000_000e18;
            optionCap = 0;
            baseCap = 0;
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("OP"))) {
            perpCap = 10_000_000e18;
            optionCap = 0;
            baseCap = 0;
        } else if (keccak256(abi.encodePacked(market)) == keccak256(abi.encodePacked("ARB"))) {
            perpCap = 10_000_000e18;
            optionCap = 0;
            baseCap = 0;
        } else {
            revert("market not supported");
        }
    }

    //////////////
    // Auctions //
    //////////////

    function getDefaultAuctionParam() public pure returns (IDutchAuction.AuctionParams memory param) {
        param = IDutchAuction.AuctionParams({
            startingMtMPercentage: 0.95e18,
            fastAuctionCutoffPercentage: 0.7e18,
            fastAuctionLength: 15 minutes,
            slowAuctionLength: 12 hours,
            insolventAuctionLength: 60 minutes,
            liquidatorFeeRate: 0.1e18,
            bufferMarginPercentage: 0.15e18
        });
    }


    ////////////
    // Assets //
    ////////////

    // cash
    function getDefaultInterestRateModel() public pure returns (
        uint minRate,
        uint rateMultiplier,
        uint highRateMultiplier,
        uint optimalUtil
    ) {
        minRate = 0.02e18;
        rateMultiplier = 0.08e18;
        highRateMultiplier = 0.9e18;
        optimalUtil = 0.85e18;
    }
    uint256 public constant CASH_SM_FEE = 0.2e18;

    // perp
    function getPerpParams() public pure returns (int staticInterestRate, int fundingRateCap, uint fundingConvergencePeriod) {
        staticInterestRate = 0.0000125e18;
        fundingRateCap = 0.004e18;
        fundingConvergencePeriod = 8e18;
    }

    ///////////
    // Feeds //
    ///////////
    uint64 public constant FORWARD_HEARTBEAT = 60 minutes;
    uint64 public constant SPOT_HEARTBEAT = 3 minutes;
    uint64 public constant SETTLEMENT_HEARTBEAT = 3 minutes;
    uint64 public constant PERP_HEARTBEAT = 15 minutes;
    uint64 public constant IMPACT_PRICE_HEARTBEAT = 20 minutes;
    uint64 public constant PERP_MAX_PERCENT_DIFF = 0.06e18;
    uint64 public constant VOL_HEARTBEAT = 20 minutes;
    uint64 public constant STABLE_HEARTBEAT = 60 minutes;
    uint64 public constant FWD_MAX_EXPIRY = 400 days;
}