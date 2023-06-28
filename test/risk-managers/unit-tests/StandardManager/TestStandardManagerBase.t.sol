pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "./StandardManagerPublic.sol";

import "lyra-utils/encoding/OptionEncoding.sol";

import "src/SubAccounts.sol";
import {IManager} from "src/interfaces/IManager.sol";
import {IAsset} from "src/interfaces/IAsset.sol";

import {IBaseManager} from "src/interfaces/IBaseManager.sol";
import "src/risk-managers/PortfolioViewer.sol";
import "test/shared/mocks/MockManager.sol";
import "test/shared/mocks/MockERC20.sol";
import "test/shared/mocks/MockPerp.sol";
import "test/shared/mocks/MockOption.sol";
import "test/shared/mocks/MockFeeds.sol";
import "test/shared/mocks/MockOptionPricing.sol";
import "test/shared/mocks/MockTrackableAsset.sol";
import "test/auction/mocks/MockCashAsset.sol";
import "../../../shared/mocks/MockSpotDiffFeed.sol";

/**
 * @dev shard contract setting up environment for testing StandardManager
 */
contract TestStandardManagerBase is Test {
  SubAccounts subAccounts;
  StandardManagerPublic manager;
  MockCash cash;
  MockERC20 usdc;
  MockERC20 weth;
  MockERC20 wbtc;

  MockPerp ethPerp;
  MockPerp btcPerp;
  MockOption ethOption;
  MockOption btcOption;
  // mocked base asset!
  MockTrackableAsset wethAsset;
  MockTrackableAsset wbtcAsset;

  MockOptionPricing btcPricing;
  MockOptionPricing ethPricing;

  PortfolioViewer portfolioViewer;

  uint ethSpot = 1500e18;
  uint btcSpot = 20000e18;

  uint expiry1;
  uint expiry2;
  uint expiry3;

  MockFeeds ethFeed;
  MockFeeds btcFeed;
  MockFeeds stableFeed;

  uint8 ethMarketId = 1;
  uint8 btcMarketId = 2;

  address alice = address(0xaa);
  address bob = address(0xbb);
  address charlie = address(0xcc);
  uint aliceAcc;
  uint bobAcc;
  uint charlieAcc;

  struct Trade {
    IAsset asset;
    int amount;
    uint subId;
  }

  function setUp() public virtual {
    subAccounts = new SubAccounts("Lyra Margin Accounts", "LyraMarginNFTs");

    usdc = new MockERC20("USDC", "USDC");

    cash = new MockCash(usdc, subAccounts);

    stableFeed = new MockFeeds();

    // Setup asset for ETH Markets
    ethPerp = new MockPerp(subAccounts);
    ethOption = new MockOption(subAccounts);
    ethFeed = new MockFeeds();
    btcFeed = new MockFeeds();

    // setup asset for BTC Markets
    btcPerp = new MockPerp(subAccounts);
    btcOption = new MockOption(subAccounts);

    // setup mock base asset (only change mark to market)
    weth = new MockERC20("weth", "weth");
    wethAsset = new MockTrackableAsset(weth, subAccounts, false); // false as it cannot go negative
    wbtc = new MockERC20("wbtc", "wbtc");
    wbtcAsset = new MockTrackableAsset(wbtc, subAccounts, false); // false as it cannot go negative

    ethPricing = new MockOptionPricing();
    btcPricing = new MockOptionPricing();

    portfolioViewer = new PortfolioViewer(subAccounts, cash);

    manager = new StandardManagerPublic(
      subAccounts,
      ICashAsset(address(cash)),
      IDutchAuction(address(0)),
      portfolioViewer
    );

    portfolioViewer.setStandardManager(manager);

    manager.setPricingModule(ethMarketId, ethPricing);
    manager.setPricingModule(btcMarketId, btcPricing);

    manager.whitelistAsset(ethPerp, ethMarketId, IStandardManager.AssetType.Perpetual);
    manager.whitelistAsset(ethOption, ethMarketId, IStandardManager.AssetType.Option);
    manager.whitelistAsset(wethAsset, ethMarketId, IStandardManager.AssetType.Base);
    manager.setOraclesForMarket(ethMarketId, ethFeed, ethFeed, ethFeed, ethFeed);

    manager.whitelistAsset(btcPerp, btcMarketId, IStandardManager.AssetType.Perpetual);
    manager.whitelistAsset(btcOption, btcMarketId, IStandardManager.AssetType.Option);
    manager.whitelistAsset(wbtcAsset, btcMarketId, IStandardManager.AssetType.Base);
    manager.setOraclesForMarket(btcMarketId, btcFeed, btcFeed, btcFeed, btcFeed);

    manager.setStableFeed(stableFeed);
    stableFeed.setSpot(1e18, 1e18);
    manager.setDepegParameters(IStandardManager.DepegParams(0.98e18, 1.3e18));

    aliceAcc = subAccounts.createAccountWithApproval(alice, address(this), manager);
    bobAcc = subAccounts.createAccountWithApproval(bob, address(this), manager);
    charlieAcc = subAccounts.createAccountWithApproval(charlie, address(this), manager);

    expiry1 = block.timestamp + 7 days;
    expiry2 = block.timestamp + 14 days;
    expiry3 = block.timestamp + 30 days;

    ethFeed.setSpot(ethSpot, 1e18);
    btcFeed.setSpot(btcSpot, 1e18);
    ethPerp.setMockPerpPrice(ethSpot, 1e18);
    btcPerp.setMockPerpPrice(btcSpot, 1e18);

    ethFeed.setForwardPrice(expiry1, ethSpot, 1e18);
    ethFeed.setForwardPrice(expiry2, ethSpot, 1e18);
    ethFeed.setForwardPrice(expiry3, ethSpot, 1e18);

    btcFeed.setForwardPrice(expiry1, btcSpot, 1e18);
    btcFeed.setForwardPrice(expiry2, btcSpot, 1e18);
    btcFeed.setForwardPrice(expiry3, btcSpot, 1e18);

    usdc.mint(address(this), 100_000e18);
    usdc.approve(address(cash), type(uint).max);

    // set init perp trading parameters
    manager.setPerpMarginRequirements(ethMarketId, 0.05e18, 0.1e18);
    manager.setPerpMarginRequirements(btcMarketId, 0.05e18, 0.1e18);

    manager.setOptionMarginParams(ethMarketId, _getDefaultOptionMarginParams());
    manager.setOptionMarginParams(btcMarketId, _getDefaultOptionMarginParams());

    // set caps
  }

  /////////////
  // Helpers //
  /////////////

  function _submitMultipleTrades(uint from, uint to, Trade[] memory trades, bytes memory managerData) internal {
    ISubAccounts.AssetTransfer[] memory transfers = new ISubAccounts.AssetTransfer[](trades.length);
    for (uint i = 0; i < trades.length; i++) {
      transfers[i] = ISubAccounts.AssetTransfer({
        fromAcc: from,
        toAcc: to,
        asset: trades[i].asset,
        subId: trades[i].subId,
        amount: trades[i].amount,
        assetData: ""
      });
    }
    subAccounts.submitTransfers(transfers, managerData);
  }

  function _getCashBalance(uint acc) public view returns (int) {
    return subAccounts.getBalance(acc, cash, 0);
  }

  function _getPerpBalance(IPerpAsset perp, uint acc) public view returns (int) {
    return subAccounts.getBalance(acc, perp, 0);
  }

  function _getDefaultOptionMarginParams() internal pure returns (IStandardManager.OptionMarginParams memory) {
    return IStandardManager.OptionMarginParams({
      maxSpotReq: 0.15e18,
      minSpotReq: 0.1e18,
      mmCallSpotReq: 0.075e18,
      mmPutSpotReq: 0.075e18,
      MMPutMtMReq: 0.075e18,
      unpairedIMScale: 1.4e18,
      unpairedMMScale: 1.2e18,
      mmOffsetScale: 1.05e18
    });
  }
}
