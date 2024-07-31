// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {OptionAsset} from "../src/assets/OptionAsset.sol";
import {WrappedERC20Asset} from "../src/assets/WrappedERC20Asset.sol";
import {LyraSpotFeed} from "../src/feeds/LyraSpotFeed.sol";
import {LyraVolFeed} from "../src/feeds/LyraVolFeed.sol";
import {LyraRateFeedStatic} from "../src/feeds/static/LyraRateFeedStatic.sol";
import {LyraForwardFeed} from "../src/feeds/LyraForwardFeed.sol";
import {BasePortfolioViewer} from "../src/risk-managers/BasePortfolioViewer.sol";
import {IManager} from "../src/interfaces/IManager.sol";

import "forge-std/console2.sol";
import {Deployment, ConfigJson, Market} from "./types.sol";
import {Utils} from "./utils.sol";

// get all default params
import "./config-mainnet.sol";


/**
 * MARKET_NAME=weth forge script scripts/deploy-market.s.sol --private-key {} --rpc {} --broadcast
 **/
contract DeploySRMOptionOnlyMarket is Utils {

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
    market.forwardFeed = new LyraForwardFeed(market.spotFeed);
    market.volFeed = new LyraVolFeed();

    // init feeds
    market.spotFeed.setHeartbeat(Config.SPOT_HEARTBEAT);
    market.volFeed.setHeartbeat(Config.VOL_HEARTBEAT);

    market.forwardFeed.setHeartbeat(Config.FORWARD_HEARTBEAT);
    market.forwardFeed.setSettlementHeartbeat(Config.SETTLEMENT_HEARTBEAT);
    market.forwardFeed.setMaxExpiry(Config.FWD_MAX_EXPIRY);
    for (uint i=0; i<config.feedSigners.length; ++i) {
      market.spotFeed.addSigner(config.feedSigners[i], true);
      market.volFeed.addSigner(config.feedSigners[i], true);
      market.forwardFeed.addSigner(config.feedSigners[i], true);
    }

    market.option = new OptionAsset(deployment.subAccounts, address(market.forwardFeed));

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

    (,
      IStandardManager.OptionMarginParams memory optionMarginParams,
      IStandardManager.OracleContingencyParams memory oracleContingencyParams,
      IStandardManager.BaseMarginParams memory baseMarginParams) = Config.getSRMParams(marketName);

    // set assets per market
    deployment.srm.whitelistAsset(market.option, marketId, IStandardManager.AssetType.Option);
    deployment.srm.whitelistAsset(market.base, marketId, IStandardManager.AssetType.Base);

    // set oracles
    deployment.srm.setOraclesForMarket(marketId, market.spotFeed, market.forwardFeed, market.volFeed);

    // set params
    deployment.srm.setOptionMarginParams(marketId, optionMarginParams);

    deployment.srm.setOracleContingencyParams(marketId, oracleContingencyParams);

    deployment.srm.setBaseAssetMarginFactor(marketId, baseMarginParams.marginFactor, baseMarginParams.IMScale);

    deployment.srmViewer.setOIFeeRateBPS(address(market.option), 0.1e18);
    deployment.srmViewer.setOIFeeRateBPS(address(market.base), 0.1e18);
    deployment.srm.setMinOIFee(10e18);

    deployment.srm.setWhitelistedCallee(address(market.spotFeed), true);
    deployment.srm.setWhitelistedCallee(address(market.forwardFeed), true);
    deployment.srm.setWhitelistedCallee(address(market.volFeed), true);
  }

  function _whitelistAndSetCapForManager(address manager, string memory marketName, Market memory market) internal {
    market.option.setWhitelistManager(manager, true);
    market.base.setWhitelistManager(manager, true);

    (, uint optionCap, uint baseCap) = Config.getSRMCaps(marketName);

    market.option.setTotalPositionCap(IManager(manager), optionCap);
    market.base.setTotalPositionCap(IManager(manager), baseCap);
  }

  /**
   * @dev write to deployments/{network}/{marketName}.json
   */
  function _writeToMarketJson(string memory name, Market memory market) internal {

    string memory objKey = "market-deployments";

    vm.serializeAddress(objKey, "option", address(market.option));
    vm.serializeAddress(objKey, "base", address(market.base));
    vm.serializeAddress(objKey, "spotFeed", address(market.spotFeed));
    vm.serializeAddress(objKey, "volFeed", address(market.volFeed));
    string memory finalObj = vm.serializeAddress(objKey, "forwardFeed", address(market.forwardFeed));

    // build path
    _writeToDeployments(name, finalObj);
  }

}