// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {OptionAsset} from "../src/assets/OptionAsset.sol";
import {WrappedERC20Asset} from "../src/assets/WrappedERC20Asset.sol";
import {LyraSpotFeed} from "../src/feeds/LyraSpotFeed.sol";
import {PerpAsset} from "../src/assets/PerpAsset.sol";
import {LyraSpotDiffFeed} from "../src/feeds/LyraSpotDiffFeed.sol";
import {BasePortfolioViewer} from "../src/risk-managers/BasePortfolioViewer.sol";
import {PMRM} from "../src/risk-managers/PMRM.sol";
import {IManager} from "../src/interfaces/IManager.sol";
import {IVolFeed} from "../src/interfaces/IVolFeed.sol";
import {IForwardFeed} from "../src/interfaces/IForwardFeed.sol";

import "forge-std/console2.sol";
import {Deployment, ConfigJson, Market} from "./types.sol";
import {Utils} from "./utils.sol";

// get all default params
import "./config-mainnet.sol";


/**
 * MARKET_NAME=AAVE PRIVATE_KEY={} MAINNET_OWNER={} forge script scripts/deploy-perp-only-market.s.sol --private-key {} --rpc-url {} --verify --verifier blockscout --verifier-url {} --broadcast --priority-gas-price 1
 **/

// MAINNET 
// RPC: https://rpc.lyra.finance
// VERIFIER: https://explorer.derive.xyz/api

// TESTNET
// RPC: https://rpc-prod-testnet-0eakp60405.t.conduit.xyz
// VERIFIER: https://explorer-prod-testnet-0eakp60405.t.conduit.xyz/api

// will need to use an API key endpoint as limits will get hit
contract DeployPerpOnlyMarket is Utils {

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
    Market memory market = _deployMarketContracts(config, deployment);
    _setCapForManager(address(deployment.srm), marketName, market);
    _whitelistManager(address(deployment.srm), market);

    if (block.chainid != 957) {
      _registerMarketToSRM(marketName, deployment, market);

      PMRM(_getV2CoreContract("ETH", "pmrm")).setWhitelistedCallee(address(market.spotFeed), true);
      PMRM(_getV2CoreContract("ETH", "pmrm")).setWhitelistedCallee(address(market.iapFeed), true);
      PMRM(_getV2CoreContract("ETH", "pmrm")).setWhitelistedCallee(address(market.ibpFeed), true);
      PMRM(_getV2CoreContract("ETH", "pmrm")).setWhitelistedCallee(address(market.perpFeed), true);

      PMRM(_getV2CoreContract("BTC", "pmrm")).setWhitelistedCallee(address(market.spotFeed), true);
      PMRM(_getV2CoreContract("BTC", "pmrm")).setWhitelistedCallee(address(market.iapFeed), true);
      PMRM(_getV2CoreContract("BTC", "pmrm")).setWhitelistedCallee(address(market.ibpFeed), true);
      PMRM(_getV2CoreContract("BTC", "pmrm")).setWhitelistedCallee(address(market.perpFeed), true);
    } else {
      _transferOwner(market, vm.envAddress("MAINNET_OWNER"));
    }

    _writeToMarketJson(marketName, market);

    vm.stopBroadcast();
  }


  /// @dev deploy all contract needed for a single market
  function _deployMarketContracts(ConfigJson memory config, Deployment memory deployment) internal returns (Market memory market)  {
    market.spotFeed = new LyraSpotFeed();

    // feeds for perp
    market.perpFeed = new LyraSpotDiffFeed(market.spotFeed);
    market.iapFeed = new LyraSpotDiffFeed(market.spotFeed);
    market.ibpFeed = new LyraSpotDiffFeed(market.spotFeed);

    // init feeds
    market.spotFeed.setHeartbeat(Config.SPOT_HEARTBEAT);

    market.perpFeed.setHeartbeat(Config.PERP_HEARTBEAT);
    market.iapFeed.setHeartbeat(Config.IMPACT_PRICE_HEARTBEAT);
    market.ibpFeed.setHeartbeat(Config.IMPACT_PRICE_HEARTBEAT);

    market.perpFeed.setSpotDiffCap(Config.PERP_MAX_PERCENT_DIFF);
    market.iapFeed.setSpotDiffCap(Config.PERP_MAX_PERCENT_DIFF);
    market.ibpFeed.setSpotDiffCap(Config.PERP_MAX_PERCENT_DIFF);

    for (uint i=0; i<config.feedSigners.length; ++i) {
      market.spotFeed.addSigner(config.feedSigners[i], true);
      market.perpFeed.addSigner(config.feedSigners[i], true);
      market.iapFeed.addSigner(config.feedSigners[i], true);
      market.ibpFeed.addSigner(config.feedSigners[i], true);
    }

    market.spotFeed.setRequiredSigners(config.requiredSigners);
    market.perpFeed.setRequiredSigners(config.requiredSigners);
    market.iapFeed.setRequiredSigners(config.requiredSigners);
    market.ibpFeed.setRequiredSigners(config.requiredSigners);

    // Deploy and configure perp
    (int staticInterestRate, int fundingRateCap, uint fundingConvergencePeriod) = Config.getPerpParams();

    market.perp = new PerpAsset(deployment.subAccounts);
    market.perp.setRateBounds(fundingRateCap);
    market.perp.setStaticInterestRate(staticInterestRate);
    if (fundingConvergencePeriod != 8e18) {
      market.perp.setConvergencePeriod(fundingConvergencePeriod);
    }

    // Add feeds to perp
    market.perp.setSpotFeed(market.spotFeed);
    market.perp.setPerpFeed(market.perpFeed);
    market.perp.setImpactFeeds(market.iapFeed, market.ibpFeed);

  }

  function _registerMarketToSRM(string memory marketName, Deployment memory deployment, Market memory market) internal {
    // find market ID
    uint marketId = deployment.srm.createMarket(marketName);

    console2.log("market ID for newly created market:", marketId);

    (
      IStandardManager.PerpMarginRequirements memory perpMarginRequirements,
      ,
      IStandardManager.OracleContingencyParams memory oracleContingencyParams,
    ) = Config.getSRMParams(marketName);

    // set assets per market
    deployment.srm.whitelistAsset(market.perp, marketId, IStandardManager.AssetType.Perpetual);

    // set oracles
    deployment.srm.setOraclesForMarket(marketId, market.spotFeed, IForwardFeed(address(0)), IVolFeed(address(0)));

    // set params
    deployment.srm.setOracleContingencyParams(marketId, oracleContingencyParams);
    deployment.srm.setPerpMarginRequirements(marketId, perpMarginRequirements.mmPerpReq, perpMarginRequirements.imPerpReq);

    deployment.srmViewer.setOIFeeRateBPS(address(market.perp), Config.OI_FEE_BPS);

    deployment.srm.setWhitelistedCallee(address(market.spotFeed), true);
    deployment.srm.setWhitelistedCallee(address(market.iapFeed), true);
    deployment.srm.setWhitelistedCallee(address(market.ibpFeed), true);
    deployment.srm.setWhitelistedCallee(address(market.perpFeed), true);
  }

  function _whitelistManager(address manager, Market memory market) internal {
    market.perp.setWhitelistManager(manager, true);
  }

  function _setCapForManager(address manager, string memory marketName, Market memory market) internal {
    (uint perpCap,, ) = Config.getSRMCaps(marketName);

    market.perp.setTotalPositionCap(IManager(manager), perpCap);
  }

  function _transferOwner(Market memory market, address newOwner) internal {
    market.perp.transferOwnership(newOwner);
    market.spotFeed.transferOwnership(newOwner);
    market.iapFeed.transferOwnership(newOwner);
    market.ibpFeed.transferOwnership(newOwner);
    market.perpFeed.transferOwnership(newOwner);

    console2.log("New owner for market: ", newOwner);
  }

  /**
   * @dev write to deployments/{network}/{marketName}.json
   */
  function _writeToMarketJson(string memory name, Market memory market) internal {

    string memory objKey = "market-deployments";

    vm.serializeAddress(objKey, "perp", address(market.perp));
    vm.serializeAddress(objKey, "spotFeed", address(market.spotFeed));
    vm.serializeAddress(objKey, "perpFeed", address(market.perpFeed));
    vm.serializeAddress(objKey, "ibpFeed", address(market.ibpFeed));
    string memory finalObj = vm.serializeAddress(objKey, "iapFeed", address(market.iapFeed));

    // build path
    _writeToDeployments(name, finalObj);
  }

}