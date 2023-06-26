// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


// import "../src/feeds/LyraSpotFeed.sol";
// import "../src/SecurityModule.sol";
// import "../src/risk-managers/PMRM.sol";
import "../src/assets/CashAsset.sol";
import "../src/assets/Option.sol";
import "../src/assets/InterestRateModel.sol";
import "../src/liquidation/DutchAuction.sol";
import "../src/SubAccounts.sol";
import "../src/SecurityModule.sol";
import "../src/risk-managers/StandardManager.sol";

import "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

import "forge-std/console2.sol";
import "./types.sol";
import {Utils} from "./utils.sol";

// get all default params
import "./config.sol";


contract Deploy is Utils {

  /// @dev main function
  function run() external {
    vm.startBroadcast();

    console2.log("Start deployment! deployer: ", msg.sender);

    // load configs
    (IERC20Metadata usdc) = _getConfig();

    // deploy core contracts
    deployCoreContracts(usdc);

    vm.stopBroadcast();
  }

  /// @dev get config from current chainId
  function _getConfig() internal view returns (IERC20Metadata usdc) {
    string memory file = readInput("config");

    bytes memory usdcAddrRaw = vm.parseJson(file);
    ConfigJson memory config = abi.decode(usdcAddrRaw, (ConfigJson));

    usdc = IERC20Metadata(config.usdc);
  }


  /// @dev deploy and initiate contracts
  function deployCoreContracts(IERC20Metadata usdc) internal returns (Deployment memory deployment)  {

    uint nonce = vm.getNonce(msg.sender);

    // nonce: nonce + 1
    deployment.subAccounts = new SubAccounts("Lyra Margin Accounts", "LyraMarginNFTs");
    
    (uint minRate, uint rateMultiplier, uint highRateMultiplier, uint optimalUtil) = getDefaultInterestRateModel();
    // nonce + 2
    deployment.rateModel = new InterestRateModel(minRate, rateMultiplier, highRateMultiplier, optimalUtil);

    // nonce + 3
    deployment.cash = new CashAsset(deployment.subAccounts, usdc, deployment.rateModel);

    // nonce + 4: Deploy SM
    address srmAddr = computeCreateAddress(msg.sender, nonce + 6);
    deployment.securityModule = new SecurityModule(deployment.subAccounts, deployment.cash, IManager(srmAddr));

    // nonce + 5: Deploy Auction
    deployment.auction = new DutchAuction(deployment.subAccounts, deployment.securityModule, deployment.cash);

    // nonce + 6: Deploy Standard Manager. Shared by all assets
    deployment.srm = new StandardManager(deployment.subAccounts, deployment.cash, deployment.auction);
    assert(address(deployment.srm) == address(srmAddr));

    // Deploy USDC stable feed
    // stableFeed = new MockFeeds();
    // stableFeed.setSpot(1e18, 1e18);

    deployment.cash.setLiquidationModule(deployment.auction);
    deployment.cash.setSmFeeRecipient(deployment.securityModule.accountId());
    

  }

}