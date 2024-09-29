pragma solidity ^0.8.0;

import "../src/assets/CashAsset.sol";
import "../src/assets/InterestRateModel.sol";
import "../src/liquidation/DutchAuction.sol";
import "../src/SubAccounts.sol";
import "../src/SecurityModule.sol";
import "../src/risk-managers/StandardManager.sol";
import "../src/risk-managers/SRMPortfolioViewer.sol";
import "../src/periphery/OracleDataSubmitter.sol";

import "../src/feeds/LyraSpotFeed.sol";

import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

import "forge-std/console2.sol";
import {Deployment, ConfigJson} from "./types.sol";
import {Utils} from "./utils.sol";

// Read from deployment config
import "./config-mainnet.sol";
import "../src/periphery/PerpSettlementHelper.sol";
import "../src/periphery/OptionSettlementHelper.sol";
import {IOptionAsset} from "../src/interfaces/IOptionAsset.sol";
import {ILiquidatableManager} from "../src/interfaces/ILiquidatableManager.sol";

// Or just call one by one
// cast send {ManagerContract} "settleOptions(address,uint256)" {OptionAsset} {SubaccountId} --rpc-url https://rpc-prod-testnet-0eakp60405.t.conduit.xyz --private-key <...> --priority-gas-price 1

/*
 * PRIVATE_KEY=<...> forge script scripts/settle-options.s.sol --private-key <...> --rpc-url https://rpc-prod-testnet-0eakp60405.t.conduit.xyz --broadcast --priority-gas-price 1
 */
contract DeployCore is Utils {
    /// @dev main function
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address deployer = vm.addr(deployerPrivateKey);
        console2.log("Start deploying core contracts! deployer: ", deployer);

        // STEP 1: define subaccount to settle (find them in admin dashboard / balances)
        // STEP 2: make sure thesea are only SRM or PMRM
        uint256[3] memory subaccountsToSettle = [
            uint256(47288),
            uint256(50310),
            uint256(77556)
        ];

        for (uint i = 0; i < subaccountsToSettle.length; i++) {
            console2.log("Settling subaccount: ", subaccountsToSettle[i]);

            // STEP 3: set PMRM or SRM as manager to call
            // ILiquidatableManager(
            //     address(0x28bE681F7bEa6f465cbcA1D25A2125fe7533391C) // [TESTNET] SRM
            ILiquidatableManager(
                address(0xDF448056d7bf3f9Ca13d713114e17f1B7470DeBF) // [TESTNET] PMRM ETH
            ).settleOptions(
                    // STEP 4: choose ETH vs BTC option asset
                    IOptionAsset(
                        address(0xBcB494059969DAaB460E0B5d4f5c2366aab79aa1)
                    ),
                    subaccountsToSettle[i]
                );
        }

        vm.stopBroadcast();
    }
}
