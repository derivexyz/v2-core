// SPDX-License-Identifier: BUSL-1.1
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

contract DeployCore is Utils {

  /// @dev main function
  function run() external {

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);

    address deployer = vm.addr(deployerPrivateKey);
    console2.log("Start deploying core contracts! deployer: ", deployer);

    // load configs
    ConfigJson memory config = _loadConfig();

    // deploy core contracts
    _deployCoreContracts(deployer, config);

    vm.stopBroadcast();
  }


  /// @dev deploy and initiate contracts
  function _deployCoreContracts(address deployer, ConfigJson memory config) internal returns (Deployment memory deployment)  {

    uint nonce = vm.getNonce(deployer);

    // nonce: nonce
    deployment.subAccounts = new SubAccounts("Lyra Margin Accounts", "LyraMarginNFTs");
    
    (uint minRate, uint rateMultiplier, uint highRateMultiplier, uint optimalUtil) = getDefaultInterestRateModel();
    // nonce + 1
    deployment.rateModel = new InterestRateModel(minRate, rateMultiplier, highRateMultiplier, optimalUtil);

    // nonce + 2
    deployment.cash = new CashAsset(deployment.subAccounts, IERC20Metadata(config.usdc), deployment.rateModel);

    // nonce + 3: Deploy SM
    address srmAddr = computeCreateAddress(deployer, nonce + 6);
    console2.log("predicted SRM addr", srmAddr);
    deployment.securityModule = new SecurityModule(deployment.subAccounts, deployment.cash, IManager(srmAddr));

    // nonce + 4: Deploy Auction
    deployment.auction = new DutchAuction(deployment.subAccounts, deployment.securityModule, deployment.cash);

    // nonce + 5: Deploy Viewer
    deployment.srmViewer = new SRMPortfolioViewer(deployment.subAccounts, deployment.cash);

    // nonce + 6: Deploy Standard Manager. Shared by all assets
    deployment.srm = new StandardManager(deployment.subAccounts, deployment.cash, deployment.auction, deployment.srmViewer);

    assert(address(deployment.srm) == address(srmAddr));

    // Deploy USDC stable feed
    LyraSpotFeed stableFeed = new LyraSpotFeed();
    stableFeed.setHeartbeat(365 days);
    deployment.stableFeed = stableFeed;

    deployment.dataSubmitter = new OracleDataSubmitter();
    deployment.perpSettlementHelper = new PerpSettlementHelper();
    deployment.optionSettlementHelper = new OptionSettlementHelper();

    _setupCoreFunctions(deployment);

    // write to output
    __writeToDeploymentsJson(deployment);
  }

  function _setupCoreFunctions(Deployment memory deployment) internal {
    deployment.srmViewer.setStandardManager(deployment.srm);

    deployment.auction.setSMAccount(deployment.securityModule.accountId());

    // setup cash
    deployment.cash.setLiquidationModule(deployment.auction);
    deployment.cash.setSmFeeRecipient(deployment.securityModule.accountId());
    deployment.cash.setSmFee(CASH_SM_FEE);

    // set parameter for auction
    deployment.auction.setAuctionParams(getDefaultAuctionParam());
    
    // allow liquidation to request payout from sm
    deployment.securityModule.setWhitelistModule(address(deployment.auction), true);

    deployment.cash.setWhitelistManager(address(deployment.srm), true);

    // global setting for SRM
    deployment.srm.setStableFeed(deployment.stableFeed);
    
    // set SRM parameters
    deployment.srm.setDepegParameters(getDefaultDepegParam());

    deployment.srm.setWhitelistedCallee(address(deployment.stableFeed), true);
    deployment.srm.setWhitelistedCallee(address(deployment.perpSettlementHelper), true);
    deployment.srm.setWhitelistedCallee(address(deployment.optionSettlementHelper), true);

    console2.log("Core contracts deployed and setup!");
  }

  /**
   * @dev write to deployments/{network}/core.json
   */
  function __writeToDeploymentsJson(Deployment memory deployment) internal {

    string memory objKey = "core-deployments";

    vm.serializeAddress(objKey, "subAccounts", address(deployment.subAccounts));
    vm.serializeAddress(objKey, "cash", address(deployment.cash));
    vm.serializeAddress(objKey, "rateModel", address(deployment.rateModel));
    vm.serializeAddress(objKey, "securityModule", address(deployment.securityModule));
    vm.serializeAddress(objKey, "auction", address(deployment.auction));
    vm.serializeAddress(objKey, "srm", address(deployment.srm));
    vm.serializeAddress(objKey, "srmViewer", address(deployment.srmViewer));
    vm.serializeAddress(objKey, "dataSubmitter", address(deployment.dataSubmitter));
    vm.serializeAddress(objKey, "optionSettlementHelper", address(deployment.optionSettlementHelper));
    vm.serializeAddress(objKey, "perpSettlementHelper", address(deployment.perpSettlementHelper));

    string memory finalObj = vm.serializeAddress(objKey, "stableFeed", address(deployment.stableFeed));

    // build path
    _writeToDeployments("core", finalObj);
  }

}