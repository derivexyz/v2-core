pragma solidity ^0.8.18;

import "forge-std/console.sol";
import "../scripts/types.sol";
import "forge-std/console2.sol";

import "../src/risk-managers/StandardManager.sol";
import "../src/risk-managers/SRMPortfolioViewer.sol";
import "../src/risk-managers/PMRM.sol";
import "openzeppelin/access/Ownable2Step.sol";
import {Utils} from "../scripts/utils.sol";
import "../scripts/config-mainnet.sol";

contract LyraForkTest is Utils {
  function setUp() external {}

  function testDeploy() external {
    // NOTE: currently skipping please run with --fork-url https://rpc.lyra.finance and comment out to test.
    return;

    vm.deal(address(0xB176A44D819372A38cee878fB0603AEd4d26C5a5), 1 ether);
    vm.startPrank(0xB176A44D819372A38cee878fB0603AEd4d26C5a5);
    StandardManager srm = StandardManager(0x28c9ddF9A3B29c2E6a561c1BC520954e5A33de5D);

    uint marketId = srm.createMarket("eBTC");
    string memory marketName = "eBTC";

    console.log("marketId:", marketId);
    ConfigJson memory config = _loadConfig();
    (
      ,
      ,
      IStandardManager.OracleContingencyParams memory oracleContingencyParams,
      IStandardManager.BaseMarginParams memory baseMarginParams
    ) = Config.getSRMParams(marketName);

    LyraSpotFeed spotFeed = LyraSpotFeed(0xb147274cB65D5285d18245594E0Bec791De7Cb46);
    WrappedERC20Asset base = WrappedERC20Asset(0x95FE344A0f420A7aC1B1E69CB1474179a40db882);
    SRMPortfolioViewer viewer = SRMPortfolioViewer(0xAA8f9D05599F1a5d5929c40342c06a5Da063a4dE);
    // THE IMPORTANT COMMANDS START HERE
    srm.whitelistAsset(base, marketId, IStandardManager.AssetType.Base);

    srm.setOraclesForMarket(marketId, spotFeed, IForwardFeed(address(0)), IVolFeed(address(0)));
    srm.setOracleContingencyParams(marketId, oracleContingencyParams);
    srm.setBaseAssetMarginFactor(marketId, baseMarginParams.marginFactor, baseMarginParams.IMScale);
    viewer.setOIFeeRateBPS(address(base), Config.OI_FEE_BPS);
    srm.setMinOIFee(Config.MIN_OI_FEE);

    srm.setWhitelistedCallee(address(spotFeed), true);
    PMRM(_getV2CoreContract("ETH", "pmrm")).setWhitelistedCallee(address(spotFeed), true);
    PMRM(_getV2CoreContract("BTC", "pmrm")).setWhitelistedCallee(address(spotFeed), true);
  }
}
