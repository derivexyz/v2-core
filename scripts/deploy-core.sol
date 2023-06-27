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
import "./types.sol";
import {Utils} from "./utils.sol";

// get all default params
import "./config.sol";


contract DeployCore is Utils {

  /// @dev main function
  function run() external {
    vm.startBroadcast();

    console2.log("Start deploying core contracts! deployer: ", msg.sender);

    // load configs
    (IERC20Metadata usdc, bool useMockedFeed) = _getConfig();

    // deploy core contracts
    deployCoreContracts(usdc, useMockedFeed);

    vm.stopBroadcast();
  }

  /// @dev get config from current chainId
  function _getConfig() internal view returns (IERC20Metadata usdc, bool useMockedFeed) {
    string memory file = readInput("config");

    bytes memory usdcAddrRaw = vm.parseJson(file);
    ConfigJson memory config = abi.decode(usdcAddrRaw, (ConfigJson));

    usdc = IERC20Metadata(config.usdc);
    useMockedFeed = config.useMockedFeed;
  }


  /// @dev deploy and initiate contracts
  function deployCoreContracts(IERC20Metadata usdc, bool useMockedStableFeed) internal returns (Deployment memory deployment)  {

    uint nonce = vm.getNonce(msg.sender);

    // nonce: nonce
    deployment.subAccounts = new SubAccounts("Lyra Margin Accounts", "LyraMarginNFTs");
    
    (uint minRate, uint rateMultiplier, uint highRateMultiplier, uint optimalUtil) = getDefaultInterestRateModel();
    // nonce + 1
    deployment.rateModel = new InterestRateModel(minRate, rateMultiplier, highRateMultiplier, optimalUtil);

    // nonce + 2
    deployment.cash = new CashAsset(deployment.subAccounts, usdc, deployment.rateModel);

    // nonce + 3: Deploy SM
    address srmAddr = computeCreateAddress(msg.sender, nonce + 5);
    deployment.securityModule = new SecurityModule(deployment.subAccounts, deployment.cash, IManager(srmAddr));

    // nonce + 4: Deploy Auction
    deployment.auction = new DutchAuction(deployment.subAccounts, deployment.securityModule, deployment.cash);

    // nonce + 5: Deploy Standard Manager. Shared by all assets
    deployment.srm = new StandardManager(deployment.subAccounts, deployment.cash, deployment.auction);
    assert(address(deployment.srm) == address(srmAddr));

    // Deploy USDC stable feed
    if (useMockedStableFeed) {
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
  }

}