// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./config-mainnet.sol";
import "forge-std/console2.sol";
import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {BasePortfolioViewer} from "../src/risk-managers/BasePortfolioViewer.sol";
import {Deployment, ConfigJson, Market} from "./types.sol";
import {IManager} from "../src/interfaces/IManager.sol";
import {IPMRM_2} from "../src/interfaces/IPMRM_2.sol";
import {LyraForwardFeed} from "../src/feeds/LyraForwardFeed.sol";
import {LyraRateFeedStatic} from "../src/feeds/static/LyraRateFeedStatic.sol";
import {LyraSpotDiffFeed} from "../src/feeds/LyraSpotDiffFeed.sol";
import {LyraSpotFeed} from "../src/feeds/LyraSpotFeed.sol";
import {LyraRateFeed} from "../src/feeds/LyraRateFeed.sol";
import {LyraVolFeed} from "../src/feeds/LyraVolFeed.sol";
import {MockSpotDiffFeed} from "../test/shared/mocks/MockSpotDiffFeed.sol";

import {OptionAsset} from "../src/assets/OptionAsset.sol";

import {PMRMLib_2} from "../src/risk-managers/PMRMLib_2.sol";
import {PMRM_2} from "../src/risk-managers/PMRM_2.sol";
import {PerpAsset} from "../src/assets/PerpAsset.sol";

// get all default params
import {TransparentUpgradeableProxy} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Utils} from "./utils.sol";
import {WrappedERC20Asset} from "../src/assets/WrappedERC20Asset.sol";

/**
 * MARKET_NAME=weth forge script scripts/deploy-market.s.sol --private-key {} --rpc {} --broadcast
 **/
contract DeployPm2Market is Utils {
  struct PM2Contracts {
    PMRM_2 pmrm2;
    PMRM_2 pmrm_imp;
    PMRMLib_2 pmrmLib_2;
    BasePortfolioViewer pmrmViewer;
    LyraRateFeed rateFeed;
  }

  /// @dev main function
  function run() external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);

    // revert if not found
    string memory marketName = vm.envString("MARKET_NAME");

    console2.log("Start deploying new market: ", marketName);
    address deployer = vm.addr(deployerPrivateKey);
    console2.log("Deployer: ", deployer);

    // load configs
    ConfigJson memory config = _loadConfig();

    // load deployed core contracts
    Deployment memory deployment = _loadDeployment();

    Market memory deployedMarket = _loadMarket(marketName);

    // deploy core contracts
    PM2Contracts memory pm2Contracts = _deployPM2Contracts(deployer, marketName, config, deployment, deployedMarket);

    _setupPMRMParams(marketName, pm2Contracts, deployedMarket, deployment);

    _setPermissionAndCaps(deployment,marketName,deployedMarket, address(pm2Contracts.pmrm2));

    _writeToMarketJson(marketName, pm2Contracts);

    vm.stopBroadcast();
  }

  function _deployPM2Contracts(
    address deployer,
    string memory marketName,
    ConfigJson memory config,
    Deployment memory deployment,
    Market memory deployedMarket
  ) internal returns (PM2Contracts memory pm2Contracts)  {
    // get the market ERC20 from config (it should be added to the config)

    pm2Contracts.rateFeed = new LyraRateFeed();
    pm2Contracts.rateFeed.setHeartbeat(Config.RATE_HEARTBEAT);
    for (uint i=0; i<config.feedSigners.length; ++i) {
      pm2Contracts.rateFeed.addSigner(config.feedSigners[i], true);
    }
    pm2Contracts.rateFeed.setRequiredSigners(config.requiredSigners);

    IPMRM_2.Feeds memory feeds = IPMRM_2.Feeds({
      spotFeed: deployedMarket.spotFeed,
      stableFeed: deployment.stableFeed,
      forwardFeed: deployedMarket.forwardFeed,
      interestRateFeed: pm2Contracts.rateFeed,
      volFeed: deployedMarket.volFeed
    });

    pm2Contracts.pmrmLib_2 = new PMRMLib_2();
    pm2Contracts.pmrmViewer = new BasePortfolioViewer(
      deployment.subAccounts,
      deployment.cash
    );

    pm2Contracts.pmrm_imp = new PMRM_2();

    TransparentUpgradeableProxy pmrm2 = new TransparentUpgradeableProxy(
      address(pm2Contracts.pmrm_imp),
      address(deployer),
      abi.encodeWithSelector(PMRM_2.initialize.selector,
        address(deployment.subAccounts),
        address(deployment.cash),
        address(deployedMarket.option),
        address(deployedMarket.perp),
        address(deployment.auction),
        feeds,
        address(pm2Contracts.pmrmViewer),
        address(pm2Contracts.pmrmLib_2),
        10
      )
    );

    pm2Contracts.pmrm2 = PMRM_2(address(pmrm2));
    return pm2Contracts;
  }

  function _setupPMRMParams(string memory marketName, PM2Contracts memory newPm, Market memory market, Deployment memory deployment) internal {
    // set PMRM parameters
    (
      IPMRMLib_2.VolShockParameters memory volShockParams,
      IPMRMLib_2.MarginParameters memory marginParams,
      IPMRMLib_2.BasisContingencyParameters memory basisContParams,
      IPMRMLib_2.OtherContingencyParameters memory otherContParams,
      IPMRMLib_2.SkewShockParameters memory skewShockParams
    ) = Config.getPMRM2Params();
    newPm.pmrmLib_2.setBasisContingencyParams(basisContParams);
    newPm.pmrmLib_2.setOtherContingencyParams(otherContParams);
    newPm.pmrmLib_2.setMarginParams(marginParams);
    newPm.pmrmLib_2.setVolShockParams(volShockParams);
    newPm.pmrmLib_2.setSkewShockParameters(skewShockParams);

    // set all scenarios!
    newPm.pmrm2.setScenarios(Config.getDefaultPM2Scenarios());
    newPm.pmrm2.setMaxAccountSize(Config.MAX_ACCOUNT_SIZE_PMRM);

    // set fees
    newPm.pmrmViewer.setOIFeeRateBPS(address(market.perp), Config.OI_FEE_BPS);
    newPm.pmrmViewer.setOIFeeRateBPS(address(market.option), Config.OI_FEE_BPS);
    newPm.pmrm2.setMinOIFee(Config.MIN_OI_FEE);

    newPm.pmrm2.setWhitelistedCallee(address(deployment.perpSettlementHelper), true);
    newPm.pmrm2.setWhitelistedCallee(address(deployment.optionSettlementHelper), true);
  }

  function _setPermissionAndCaps(Deployment memory deployment, string memory marketName, Market memory market, address manager) internal {
    deployment.auction.setWhitelistManager(manager, true);
    deployment.cash.setWhitelistManager(manager, true);
    _whitelistAndSetCapForManager(manager, marketName, market);
  }

  function _whitelistAndSetCapForManager(address manager, string memory marketName, Market memory market) internal {
    market.option.setWhitelistManager(manager, true);
    market.perp.setWhitelistManager(manager, true);

    (uint perpCap, uint optionCap, ) = Config.getSRMCaps(marketName);

    market.option.setTotalPositionCap(IManager(manager), optionCap);
    market.perp.setTotalPositionCap(IManager(manager), perpCap);
  }

  function _writeToMarketJson(string memory marketName, PM2Contracts memory pm2Contracts) internal {
    string memory deploymentDir = string.concat(vm.projectRoot(), "/deployments/");
    string memory chainDir = string.concat(vm.toString(block.chainid), "/");
    string memory file = string.concat(marketName, "_2.json");

    string memory path = string.concat(deploymentDir, chainDir, file);
    vm.serializeAddress("PMRM2", "rateFeed", address(pm2Contracts.rateFeed));
    vm.serializeAddress("PMRM2", "pmrm2", address(pm2Contracts.pmrm2));
    vm.serializeAddress("PMRM2", "pmrm2Imp", address(pm2Contracts.pmrm_imp));
    vm.serializeAddress("PMRM2", "pmrmLib2", address(pm2Contracts.pmrmLib_2));
    string memory json = vm.serializeAddress("PMRM2", "pmrmViewer2", address(pm2Contracts.pmrmViewer));
    vm.writeJson(json, path);
  }
}