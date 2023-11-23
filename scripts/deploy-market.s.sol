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

import {MockSpotDiffFeed} from "../test/shared/mocks/MockSpotDiffFeed.sol";

import "forge-std/console2.sol";
import {Deployment, ConfigJson, Market} from "./types.sol";
import {Utils} from "./utils.sol";

// get all default params
import "./config-mainnet.sol";


/**
 * MARKET_NAME=weth forge script scripts/deploy-market.s.sol --private-key {} --rpc {} --broadcast
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

    _setupPerpAsset(market);

    _setupPMRMParams(marketName, market, deployment);

    _registerMarketToSRM(marketName, deployment, market);

    _writeToMarketJson(marketName, market);

    vm.stopBroadcast();
  }


  /// @dev deploy all contract needed for a single market
  function _deployMarketContracts(string memory marketName, ConfigJson memory config, Deployment memory deployment) internal returns (Market memory market)  {
    // get the market ERC20 from config (it should be added to the config)
    address marketERC20 = _getMarketERC20(marketName, config);

    console2.log("target erc20:", marketERC20);

    market.spotFeed = new LyraSpotFeed();
    market.forwardFeed = new LyraForwardFeed(market.spotFeed);
    // feeds for perp
    market.perpFeed = new LyraSpotDiffFeed(market.spotFeed);
    market.iapFeed = new LyraSpotDiffFeed(market.spotFeed);
    market.ibpFeed = new LyraSpotDiffFeed(market.spotFeed);

    // interest and vol feed
    market.rateFeed = new LyraRateFeedStatic();

    market.volFeed = new LyraVolFeed();

    // init feeds
    market.spotFeed.setHeartbeat(Config.SPOT_HEARTBEAT);
    market.volFeed.setHeartbeat(Config.VOL_HEARTBEAT);
    market.perpFeed.setHeartbeat(Config.PERP_HEARTBEAT);
    market.iapFeed.setHeartbeat(Config.IMPACT_PRICE_HEARTBEAT);
    market.ibpFeed.setHeartbeat(Config.IMPACT_PRICE_HEARTBEAT);

    market.perpFeed.setSpotDiffCap(Config.PERP_MAX_PERCENT_DIFF);
    market.iapFeed.setSpotDiffCap(Config.PERP_MAX_PERCENT_DIFF);
    market.ibpFeed.setSpotDiffCap(Config.PERP_MAX_PERCENT_DIFF);

    market.forwardFeed.setHeartbeat(Config.FORWARD_HEARTBEAT);
    market.forwardFeed.setSettlementHeartbeat(Config.SETTLEMENT_HEARTBEAT);
    market.forwardFeed.setMaxExpiry(Config.FWD_MAX_EXPIRY);
    for (uint i=0; i<config.feedSigners.length; ++i) {
      market.spotFeed.addSigner(config.feedSigners[i], true);
      market.perpFeed.addSigner(config.feedSigners[i], true);
      market.iapFeed.addSigner(config.feedSigners[i], true);
      market.ibpFeed.addSigner(config.feedSigners[i], true);
      market.volFeed.addSigner(config.feedSigners[i], true);
      market.forwardFeed.addSigner(config.feedSigners[i], true);
    }

  market.option = new OptionAsset(deployment.subAccounts, address(market.forwardFeed));

    (int staticInterestRate, int fundingRateCap, uint fundingConvergencePeriod) = Config.getPerpParams();

    market.perp = new PerpAsset(deployment.subAccounts);
    market.perp.setRateBounds(fundingRateCap);
    market.perp.setStaticInterestRate(staticInterestRate);
    if (fundingConvergencePeriod != 8e18) {
      market.perp.setConvergencePeriod(fundingConvergencePeriod);
    }

    market.rateFeed.setRate(0, 1e18);

    market.base = new WrappedERC20Asset(deployment.subAccounts, IERC20Metadata(marketERC20));


    IPMRM.Feeds memory feeds = IPMRM.Feeds({
      spotFeed: market.spotFeed,
      stableFeed: deployment.stableFeed,
      forwardFeed: market.forwardFeed,
      interestRateFeed: market.rateFeed,
      volFeed: market.volFeed
    });

    market.pmrmLib = new PMRMLib();
    market.pmrmViewer = new BasePortfolioViewer(deployment.subAccounts, deployment.cash);

    market.pmrm = new PMRM(
      deployment.subAccounts, 
      deployment.cash, 
      market.option, 
      market.perp, 
      market.base, 
      deployment.auction,
      feeds,
      market.pmrmViewer,
      market.pmrmLib
    );
  }

  function _setupPMRMParams(string memory marketName, Market memory market, Deployment memory deployment) internal {
    // set PMRM parameters
    (
      IPMRMLib.BasisContingencyParameters memory basisContParams,
      IPMRMLib.OtherContingencyParameters memory otherContParams,
      IPMRMLib.MarginParameters memory marginParams,
      IPMRMLib.VolShockParameters memory volShockParams
    ) = Config.getPMRMParams();
    market.pmrmLib.setBasisContingencyParams(basisContParams);
    market.pmrmLib.setOtherContingencyParams(otherContParams);
    market.pmrmLib.setMarginParams(marginParams);
    market.pmrmLib.setVolShockParams(volShockParams);

    // set all scenarios!
    market.pmrm.setScenarios(Config.getDefaultScenarios());
    market.pmrm.setMaxAccountSize(Config.MAX_ACCOUNT_SIZE_PMRM);

    // set fees
    market.pmrmViewer.setOIFeeRateBPS(address(market.perp), Config.OI_FEE_BPS);
    market.pmrmViewer.setOIFeeRateBPS(address(market.option), Config.OI_FEE_BPS);
    market.pmrmViewer.setOIFeeRateBPS(address(market.base), Config.OI_FEE_BPS);
    market.pmrm.setMinOIFee(Config.MIN_OI_FEE);

    market.pmrm.setWhitelistedCallee(address(market.spotFeed), true);
    market.pmrm.setWhitelistedCallee(address(market.iapFeed), true);
    market.pmrm.setWhitelistedCallee(address(market.ibpFeed), true);
    market.pmrm.setWhitelistedCallee(address(market.perpFeed), true);
    market.pmrm.setWhitelistedCallee(address(market.forwardFeed), true);
    market.pmrm.setWhitelistedCallee(address(market.volFeed), true);

    market.pmrm.setWhitelistedCallee(address(deployment.perpSettlementHelper), true);
    market.pmrm.setWhitelistedCallee(address(deployment.optionSettlementHelper), true);
  }

  function _setupPerpAsset(Market memory market) internal {
    // set perp asset params
    market.perp.setSpotFeed(market.spotFeed);
    market.perp.setPerpFeed(market.perpFeed);
    market.perp.setImpactFeeds(market.iapFeed, market.ibpFeed);
  }

  function _setPermissionAndCaps(Deployment memory deployment, string memory marketName, Market memory market) internal {
    deployment.cash.setWhitelistManager(address(market.pmrm), true);

    // each asset whitelist the newly deployed PMRM
    _whitelistAndSetCapForManager(address(market.pmrm), marketName, market);
    // each asset whitelist the standard manager
    _whitelistAndSetCapForManager(address(deployment.srm), marketName, market);
    console2.log("All asset whitelist both managers!");
  }

  function _registerMarketToSRM(string memory marketName, Deployment memory deployment, Market memory market) internal {
    // find market ID
    uint marketId = deployment.srm.createMarket(marketName);

    console2.log("market ID for newly created market:", marketId);

    (IStandardManager.PerpMarginRequirements memory perpMarginRequirements,
      IStandardManager.OptionMarginParams memory optionMarginParams,
      IStandardManager.OracleContingencyParams memory oracleContingencyParams,
      IStandardManager.BaseMarginParams memory baseMarginParams) = Config.getSRMParams(marketName);

    // set assets per market
    deployment.srm.whitelistAsset(market.perp, marketId, IStandardManager.AssetType.Perpetual);
    deployment.srm.whitelistAsset(market.option, marketId, IStandardManager.AssetType.Option);
    deployment.srm.whitelistAsset(market.base, marketId, IStandardManager.AssetType.Base);

    // set oracles
    deployment.srm.setOraclesForMarket(marketId, market.spotFeed, market.forwardFeed, market.volFeed);

    // set params
    deployment.srm.setOptionMarginParams(marketId, optionMarginParams);

    deployment.srm.setOracleContingencyParams(marketId, oracleContingencyParams);

    deployment.srm.setPerpMarginRequirements(marketId, perpMarginRequirements.mmPerpReq, perpMarginRequirements.imPerpReq);

    deployment.srm.setBaseAssetMarginFactor(marketId, baseMarginParams.marginFactor, baseMarginParams.IMScale);

    deployment.srmViewer.setOIFeeRateBPS(address(market.perp), Config.OI_FEE_BPS);
    deployment.srmViewer.setOIFeeRateBPS(address(market.option), Config.OI_FEE_BPS);
    deployment.srmViewer.setOIFeeRateBPS(address(market.base), Config.OI_FEE_BPS);
    deployment.srm.setMinOIFee(Config.MIN_OI_FEE);

    deployment.srm.setWhitelistedCallee(address(market.spotFeed), true);
    deployment.srm.setWhitelistedCallee(address(market.iapFeed), true);
    deployment.srm.setWhitelistedCallee(address(market.ibpFeed), true);
    deployment.srm.setWhitelistedCallee(address(market.perpFeed), true);
    deployment.srm.setWhitelistedCallee(address(market.forwardFeed), true);
    deployment.srm.setWhitelistedCallee(address(market.volFeed), true);
  }

  function _whitelistAndSetCapForManager(address manager, string memory marketName, Market memory market) internal {
    market.option.setWhitelistManager(manager, true);
    market.base.setWhitelistManager(manager, true);
    market.perp.setWhitelistManager(manager, true);

    (uint perpCap, uint optionCap, uint baseCap) = Config.getSRMCaps(marketName);

    market.option.setTotalPositionCap(IManager(manager), optionCap);
    market.perp.setTotalPositionCap(IManager(manager), perpCap);
    market.base.setTotalPositionCap(IManager(manager), baseCap);
  }

  /**
   * @dev write to deployments/{network}/{marketName}.json
   */
  function _writeToMarketJson(string memory name, Market memory market) internal {

    string memory objKey = "market-deployments";

    vm.serializeAddress(objKey, "option", address(market.option));
    vm.serializeAddress(objKey, "perp", address(market.perp));
    vm.serializeAddress(objKey, "base", address(market.base));
    vm.serializeAddress(objKey, "spotFeed", address(market.spotFeed));
    vm.serializeAddress(objKey, "perpFeed", address(market.perpFeed));
    vm.serializeAddress(objKey, "iapFeed", address(market.iapFeed));
    vm.serializeAddress(objKey, "ibpFeed", address(market.ibpFeed));
    vm.serializeAddress(objKey, "volFeed", address(market.volFeed));
    vm.serializeAddress(objKey, "rateFeed", address(market.rateFeed));
    vm.serializeAddress(objKey, "forwardFeed", address(market.forwardFeed));
    vm.serializeAddress(objKey, "pmrm", address(market.pmrm));
    vm.serializeAddress(objKey, "pmrmLib", address(market.pmrmLib));
    string memory finalObj = vm.serializeAddress(objKey, "pmrmViewer", address(market.pmrmViewer));

    // build path
    _writeToDeployments(name, finalObj);
  }

}