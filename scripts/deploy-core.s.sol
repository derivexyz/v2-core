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


contract DeployCore is Utils {

  /// @dev main function
  function run() external {
    vm.startBroadcast();

    console2.log("Start deploying core contracts! deployer: ", msg.sender);

    // load configs
    ConfigJson memory config = _getConfig();

    // deploy core contracts
    _deployCoreContracts(config);

    vm.stopBroadcast();
  }

  /// @dev get config from current chainId
  function _getConfig() internal view returns (ConfigJson memory config) {
    string memory file = readInput("config");

    bytes memory content = vm.parseJson(file);
    config = abi.decode(content, (ConfigJson));
  }


  /// @dev deploy and initiate contracts
  function _deployCoreContracts(ConfigJson memory config) internal returns (Deployment memory deployment)  {

    uint nonce = vm.getNonce(msg.sender);

    // nonce: nonce
    deployment.subAccounts = new SubAccounts("Lyra Margin Accounts", "LyraMarginNFTs");
    
    (uint minRate, uint rateMultiplier, uint highRateMultiplier, uint optimalUtil) = getDefaultInterestRateModel();
    // nonce + 1
    deployment.rateModel = new InterestRateModel(minRate, rateMultiplier, highRateMultiplier, optimalUtil);

    // nonce + 2
    deployment.cash = new CashAsset(deployment.subAccounts, IERC20Metadata(config.usdc), deployment.rateModel);

    // nonce + 3: Deploy SM
    address srmAddr = computeCreateAddress(msg.sender, nonce + 5);
    deployment.securityModule = new SecurityModule(deployment.subAccounts, deployment.cash, IManager(srmAddr));

    // nonce + 4: Deploy Auction
    deployment.auction = new DutchAuction(deployment.subAccounts, deployment.securityModule, deployment.cash);

    // nonce + 5: Deploy Standard Manager. Shared by all assets
    deployment.srm = new StandardManager(deployment.subAccounts, deployment.cash, deployment.auction);
    assert(address(deployment.srm) == address(srmAddr));

    // Deploy USDC stable feed
    if (config.useMockedFeed) {
      MockFeeds stableFeed = new MockFeeds();
      stableFeed.setSpot(1e18, 1e18);
      deployment.stableFeed = stableFeed;
    } else {
      LyraSpotFeed stableFeed = new LyraSpotFeed();
      stableFeed.setHeartbeat(365 days);
      deployment.stableFeed = stableFeed;
    }
    
    deployment.cash.setLiquidationModule(deployment.auction);
    deployment.cash.setSmFeeRecipient(deployment.securityModule.accountId());

    // write to output
    _writeToDeploymentsJson(deployment);
  }

  /**
   * @dev write to deployments/{network}/core.json
   */
  function _writeToDeploymentsJson(Deployment memory deployment) internal {

    string memory objKey = "core-deployments";

    vm.serializeAddress(objKey, "subAccounts", address(deployment.subAccounts));
    vm.serializeAddress(objKey, "cash", address(deployment.cash));
    vm.serializeAddress(objKey, "rateModel", address(deployment.rateModel));
    vm.serializeAddress(objKey, "securityModule", address(deployment.securityModule));
    vm.serializeAddress(objKey, "auction", address(deployment.auction));
    vm.serializeAddress(objKey, "srm", address(deployment.srm));
    string memory finalObj = vm.serializeAddress(objKey, "stableFeed", address(deployment.stableFeed));

    // build path
    writeToDeployments("core", finalObj);
  }

}