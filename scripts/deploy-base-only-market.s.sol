// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {OptionAsset} from "../src/assets/OptionAsset.sol";
import {PerpAsset} from "../src/assets/PerpAsset.sol";
import {WrappedERC20Asset} from "../src/assets/WrappedERC20Asset.sol";
import {LyraSpotFeed} from "../src/feeds/LyraSpotFeed.sol";
import {LyraSpotDiffFeed} from "../src/feeds/LyraSpotDiffFeed.sol";
import {LyraVolFeed} from "../src/feeds/LyraVolFeed.sol";
import {LyraRateFeedStatic} from "../src/feeds/LyraRateFeedStatic.sol";
import {LyraForwardFeed} from "../src/feeds/LyraForwardFeed.sol";
import {PMRM} from "../src/risk-managers/PMRM.sol";
import {PMRMLib} from "../src/risk-managers/PMRMLib.sol";
import {BasePortfolioViewer} from "../src/risk-managers/BasePortfolioViewer.sol";
import {IPMRM} from "../src/interfaces/IPMRM.sol";
import {IManager} from "../src/interfaces/IManager.sol";
import {IStandardManager} from "../src/interfaces/IStandardManager.sol";
import {IForwardFeed} from "../src/interfaces/IForwardFeed.sol";
import {IVolFeed} from "../src/interfaces/IVolFeed.sol";

import {MockSpotDiffFeed} from "../test/shared/mocks/MockSpotDiffFeed.sol";

import "forge-std/console2.sol";
import {Deployment, ConfigJson, Market} from "./types.sol";
import {Utils} from "./utils.sol";

// get all default params
import "./config-mainnet.sol";


/**
 * MARKET_NAME=usdt forge script scripts/deploy-base-only-market.s.sol --private-key {} --rpc {} --broadcast
 **/
contract DeployMarket is Utils {

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

    // deploy core contracts
    Market memory market = _deployMarketContracts(marketName, config, deployment);

    _setPermissionAndCaps(deployment, marketName, market);
    _registerMarketToSRM(marketName, deployment, market);
    _writeToMarketJson(marketName, market);

    vm.stopBroadcast();
  }


  /// @dev deploy all contract needed for a single market
  function _deployMarketContracts(string memory marketName, ConfigJson memory config, Deployment memory deployment) internal returns (Market memory market)  {
    // get the market ERC20 from config (it should be added to the config)
    address marketERC20 = _getMarketERC20(marketName);

    console2.log("target erc20:", marketERC20);

    market.spotFeed = new LyraSpotFeed();

    // init feeds
    market.spotFeed.setHeartbeat(Config.SPOT_HEARTBEAT);

    for (uint i=0; i<config.feedSigners.length; ++i) {
      market.spotFeed.addSigner(config.feedSigners[i], true);
    }

    market.base = new WrappedERC20Asset(deployment.subAccounts, IERC20Metadata(marketERC20));
  }

  function _setPermissionAndCaps(Deployment memory deployment, string memory marketName, Market memory market) internal {
    // each asset whitelist the standard manager
    _whitelistAndSetCapForManager(address(deployment.srm), marketName, market);
    console2.log("All asset whitelist both managers!");
  }

  function _registerMarketToSRM(string memory marketName, Deployment memory deployment, Market memory market) internal {
    // find market ID
    uint marketId = deployment.srm.createMarket(marketName);

    console2.log("market ID for newly created market:", marketId);

    (,,IStandardManager.OracleContingencyParams memory oracleContingencyParams,
      IStandardManager.BaseMarginParams memory baseMarginParams) = Config.getSRMParams(marketName);

    // set assets per market
    deployment.srm.whitelistAsset(market.base, marketId, IStandardManager.AssetType.Base);

    deployment.srm.setOraclesForMarket(marketId, market.spotFeed, IForwardFeed(address(0)), IVolFeed(address(0)));
    deployment.srm.setOracleContingencyParams(marketId, oracleContingencyParams);
    deployment.srm.setBaseAssetMarginFactor(marketId, baseMarginParams.marginFactor, baseMarginParams.IMScale);

    deployment.srmViewer.setOIFeeRateBPS(address(market.base), Config.OI_FEE_BPS);
    deployment.srm.setMinOIFee(Config.MIN_OI_FEE);

    deployment.srm.setWhitelistedCallee(address(market.spotFeed), true);
  }

  function _whitelistAndSetCapForManager(address manager, string memory marketName, Market memory market) internal {
    market.base.setWhitelistManager(manager, true);

    (, , uint baseCap) = Config.getSRMCaps(marketName);

    market.base.setTotalPositionCap(IManager(manager), baseCap);
  }

  /**
   * @dev write to deployments/{network}/{marketName}.json
   */
  function _writeToMarketJson(string memory name, Market memory market) internal {

    string memory objKey = "market-deployments";

    vm.serializeAddress(objKey, "base", address(market.base));
    string memory finalObj = vm.serializeAddress(objKey, "spotFeed", address(market.spotFeed));

    // build path
    _writeToDeployments(name, finalObj);
  }

}