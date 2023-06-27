// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import "../src/assets/CashAsset.sol";
import "../src/assets/InterestRateModel.sol";
import "../src/liquidation/DutchAuction.sol";
import "../src/SubAccounts.sol";
import "../src/SecurityModule.sol";
import "../src/risk-managers/StandardManager.sol";

import "../src/feeds/LyraSpotFeed.sol";

import "../test/shared/mocks/MockFeeds.sol";

import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

import "forge-std/console2.sol";
import {Deployment, ConfigJson} from "./types.sol";
import {Utils} from "./utils.sol";

// get all default params
import "./config.sol";


/**
 * MARKET_NAME=weth forge script scripts/deploy-market.s.sol --private-key {} --rpc {} --broadcast
 **/
contract DeployMarket is Utils {

  /// @dev main function
  function run() external {
    vm.startBroadcast();

    // revert if not found
    string memory marketName = vm.envString("MARKET_NAME");

    console2.log("Start deploying new market: ", marketName);
    console2.log("Deployer: ", msg.sender);

    // load configs
    ConfigJson memory config = _getConfig();
    // load core deployments

    // deploy core contracts
    deployCoreContracts(config, useMockedFeed);

    vm.stopBroadcast();
  }


  /// @dev deploy and initiate contracts
  function _deployMarketContracts(ConfigJson memory config) internal returns (Deployment memory deployment)  {

  }

  /**
   * @dev write to deployments/{network}/core.json
   */
  function __writeToDeploymentsJson(Deployment memory deployment) internal {

    string memory objKey = "market-deployments";

    // vm.serializeAddress(objKey, "subAccounts", address(deployment.subAccounts));
    // vm.serializeAddress(objKey, "cash", address(deployment.cash));
    // vm.serializeAddress(objKey, "rateModel", address(deployment.rateModel));
    // vm.serializeAddress(objKey, "securityModule", address(deployment.securityModule));
    // vm.serializeAddress(objKey, "auction", address(deployment.auction));
    // vm.serializeAddress(objKey, "srm", address(deployment.srm));
    // string memory finalObj = vm.serializeAddress(objKey, "stableFeed", address(deployment.stableFeed));

    // build path
    // _writeToDeployments("core", finalObj);
  }

}