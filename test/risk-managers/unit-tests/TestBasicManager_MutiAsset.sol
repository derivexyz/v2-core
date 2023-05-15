pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "src/risk-managers/BasicManager.sol";

import "lyra-utils/encoding/OptionEncoding.sol";

import "src/Accounts.sol";
import {IManager} from "src/interfaces/IManager.sol";
import {IAsset} from "src/interfaces/IAsset.sol";

import {IBaseManager} from "src/interfaces/IBaseManager.sol";

import "test/shared/mocks/MockManager.sol";
import "test/shared/mocks/MockERC20.sol";
import "test/shared/mocks/MockPerp.sol";
import "test/shared/mocks/MockOption.sol";
import "test/shared/mocks/MockFeeds.sol";
import "test/shared/mocks/MockOptionPricing.sol";

import "test/auction/mocks/MockCashAsset.sol";

/**
 * Focusing on the margin rules for options
 */
contract UNIT_TestBasicManager_MultiAsset is Test {
  Accounts account;
  BasicManager manager;
  MockCash cash;
  MockERC20 usdc;

  MockPerp ethPerp;
  MockPerp btcPerp;
  MockOption ethOption;
  MockOption btcOption;

  MockOptionPricing pricing;
  uint expiry1;
  uint expiry2;
  uint expiry3;

  MockFeeds ethFeed;
  MockFeeds btcFeed;

  address alice = address(0xaa);
  address bob = address(0xbb);
  uint aliceAcc;
  uint bobAcc;

  struct Trade {
    IAsset asset;
    int amount;
    uint subId;
  }

  function setUp() public {
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    usdc = new MockERC20("USDC", "USDC");

    cash = new MockCash(usdc, account);

    // Setup asset for ETH Markets
    ethPerp = new MockPerp(account);
    ethOption = new MockOption(account);
    ethFeed = new MockFeeds();

    // setup asset for BTC Markets
    btcPerp = new MockPerp(account);
    btcOption = new MockOption(account);
    btcFeed = new MockFeeds();

    pricing = new MockOptionPricing();

    manager = new BasicManager(
      account,
      ICashAsset(address(cash))
    );

    manager.setPricingModule(pricing);

    manager.whitelistAsset(ethPerp, 1, IBasicManager.AssetType.Perpetual);
    manager.whitelistAsset(ethOption, 1, IBasicManager.AssetType.Option);
    manager.setOraclesForMarket(1, ethFeed, ethFeed, ethFeed);

    manager.whitelistAsset(btcPerp, 2, IBasicManager.AssetType.Perpetual);
    manager.whitelistAsset(btcOption, 2, IBasicManager.AssetType.Option);
    manager.setOraclesForMarket(2, btcFeed, btcFeed, btcFeed);

    aliceAcc = account.createAccountWithApproval(alice, address(this), manager);
    bobAcc = account.createAccountWithApproval(bob, address(this), manager);

    expiry1 = block.timestamp + 7 days;
    expiry2 = block.timestamp + 14 days;
    expiry3 = block.timestamp + 30 days;

    uint ethSpot = 1500e18;
    uint btcSpot = 20000e18;

    ethFeed.setSpot(ethSpot, 1e18);
    btcFeed.setSpot(btcSpot, 1e18);

    ethFeed.setForwardPrice(expiry1, ethSpot, 1e18);
    ethFeed.setForwardPrice(expiry2, ethSpot, 1e18);
    ethFeed.setForwardPrice(expiry3, ethSpot, 1e18);

    btcFeed.setForwardPrice(expiry1, btcSpot, 1e18);
    btcFeed.setForwardPrice(expiry2, btcSpot, 1e18);
    btcFeed.setForwardPrice(expiry3, btcSpot, 1e18);

    usdc.mint(address(this), 100_000e18);
    usdc.approve(address(cash), type(uint).max);

    // set init perp trading parameters
    manager.setPerpMarginRequirements(1, 0.05e18, 0.1e18);
    manager.setPerpMarginRequirements(2, 0.05e18, 0.1e18);

    IBasicManager.OptionMarginParameters memory params =
      IBasicManager.OptionMarginParameters(0.2e18, 0.1e18, 0.08e18, 0.125e18);

    manager.setOptionMarginParameters(1, params);
  }

  function testCanTradeMultipleMarkets() public {
    // summarize the initial margin for 2 options
    uint ethStrike = 2000e18;
    uint btcStrike = 30000e18;
    int ethMargin = manager.getIsolatedMargin(1, ethStrike, expiry1, true, -1e18, false);
    int btcMargin = manager.getIsolatedMargin(2, btcStrike, expiry1, true, -1e18, false);

    int neededMargin = ethMargin + btcMargin;
    cash.deposit(aliceAcc, uint(-neededMargin));

    // short 1 eth call + 1 btc call
    Trade[] memory trades = new Trade[](2);
    trades[0] = Trade(ethOption, 1e18, OptionEncoding.toSubId(expiry1, ethStrike, true));
    trades[1] = Trade(btcOption, 1e18, OptionEncoding.toSubId(expiry1, btcStrike, true));
    _submitMultipleTrades(aliceAcc, bobAcc, trades, "");

    int requirement = manager.getMargin(aliceAcc, false);
    assertEq(requirement, neededMargin);
  }

  function testCanTradeMultiMarketMultiExpiry() public {
    // summarize the initial margin for 2 options
    uint ethStrike = 2000e18;
    uint btcStrike = 30000e18;
    int ethMargin1 = manager.getIsolatedMargin(1, ethStrike, expiry1, true, -1e18, false);
    int btcMargin1 = manager.getIsolatedMargin(2, btcStrike, expiry1, true, -1e18, false);
    int ethMargin2 = manager.getIsolatedMargin(1, ethStrike, expiry2, true, -1e18, false);
    int btcMargin2 = manager.getIsolatedMargin(2, btcStrike, expiry2, true, -1e18, false);

    int neededMargin = ethMargin1 + btcMargin1 + ethMargin2 + btcMargin2;
    cash.deposit(aliceAcc, uint(-neededMargin));

    Trade[] memory trades = new Trade[](4);
    trades[0] = Trade(ethOption, 1e18, OptionEncoding.toSubId(expiry1, ethStrike, true));
    trades[1] = Trade(btcOption, 1e18, OptionEncoding.toSubId(expiry1, btcStrike, true));
    trades[2] = Trade(ethOption, 1e18, OptionEncoding.toSubId(expiry2, ethStrike, true));
    trades[3] = Trade(btcOption, 1e18, OptionEncoding.toSubId(expiry2, btcStrike, true));

    // short 1 eth call + 1 btc call
    _submitMultipleTrades(aliceAcc, bobAcc, trades, "");

    int requirement = manager.getMargin(aliceAcc, false);
    assertEq(requirement, neededMargin);
  }

  function testCanTradeMultiMarketOptionPerps() public {
    // summarize the initial margin for 2 options
    uint ethStrike = 2000e18;
    uint btcStrike = 30000e18;
    int ethMargin1 = manager.getIsolatedMargin(1, ethStrike, expiry1, true, -1e18, false);
    int btcMargin1 = manager.getIsolatedMargin(2, btcStrike, expiry1, true, -1e18, false);
    int ethPerpMargin = -150e18;
    int btcPerpMargin = -2000e18;
    int neededMargin = ethMargin1 + btcMargin1 + ethPerpMargin + btcPerpMargin;

    cash.deposit(aliceAcc, uint(-neededMargin));
    cash.deposit(bobAcc, uint(-ethPerpMargin - btcPerpMargin));

    Trade[] memory trades = new Trade[](4);
    trades[0] = Trade(ethOption, 1e18, OptionEncoding.toSubId(expiry1, ethStrike, true));
    trades[1] = Trade(btcOption, 1e18, OptionEncoding.toSubId(expiry1, btcStrike, true));
    trades[2] = Trade(ethPerp, 1e18, 0);
    trades[3] = Trade(btcPerp, 1e18, 0);

    // short 1 eth call + 1 btc call
    _submitMultipleTrades(aliceAcc, bobAcc, trades, "");

    int requirement = manager.getMargin(aliceAcc, false);
    assertEq(requirement, neededMargin);
  }

  function testCanTradeMultiMarketsNotInOrder() public {
    // Setup doge market
    MockOption dogeOption = new MockOption(account);
    MockFeeds dogeFeed = new MockFeeds();
    dogeFeed.setSpot(0.0005e18, 1e18);

    dogeFeed.setForwardPrice(expiry1, 0.0005e18, 1e18);

    manager.whitelistAsset(dogeOption, 5, IBasicManager.AssetType.Option);
    manager.setOraclesForMarket(5, dogeFeed, dogeFeed, dogeFeed);

    // summarize the initial margin for 2 options
    uint ethStrike = 2000e18;
    uint dogeStrike = 0.0006e18;
    int ethMargin1 = manager.getIsolatedMargin(1, ethStrike, expiry1, true, -1e18, false);
    int dogeMargin1 = manager.getIsolatedMargin(5, dogeStrike, expiry1, true, -1000e18, false);

    int ethPerpMargin = -150e18;
    int btcPerpMargin = -2000e18;
    int neededMargin = ethMargin1 + dogeMargin1 + ethPerpMargin + btcPerpMargin;

    cash.deposit(aliceAcc, uint(-neededMargin));
    cash.deposit(bobAcc, uint(-ethPerpMargin - btcPerpMargin));

    Trade[] memory trades = new Trade[](4);
    trades[0] = Trade(ethOption, 1e18, OptionEncoding.toSubId(expiry1, ethStrike, true));
    trades[1] = Trade(dogeOption, 1000e18, OptionEncoding.toSubId(expiry1, dogeStrike, true));
    trades[2] = Trade(ethPerp, 1e18, 0);
    trades[3] = Trade(btcPerp, 1e18, 0);

    _submitMultipleTrades(aliceAcc, bobAcc, trades, "");

    int requirement = manager.getMargin(aliceAcc, false);
    assertEq(requirement, neededMargin);
  }

  function testPassMultipleManagerData() public {
    cash.deposit(aliceAcc, 10000e18);

    // oracle data
    uint ethSpot = 2100e18;
    uint btcSpot = 30100e18;
    IBaseManager.ManagerData[] memory oracleData = new IBaseManager.ManagerData[](2);
    oracleData[0] = IBaseManager.ManagerData({receiver: address(ethFeed), data: abi.encode(ethSpot)});
    oracleData[1] = IBaseManager.ManagerData({receiver: address(btcFeed), data: abi.encode(btcSpot)});
    bytes memory managerData = abi.encode(oracleData);

    // build trades
    uint strike = 2500e18;
    Trade[] memory trades = new Trade[](1);
    trades[0] = Trade(ethOption, 1e18, OptionEncoding.toSubId(expiry1, strike, true));

    _submitMultipleTrades(aliceAcc, bobAcc, trades, managerData);

    (uint _ethSpot,) = ethFeed.getSpot();
    (uint _btcSpot,) = btcFeed.getSpot();
    assertEq(_ethSpot, ethSpot);
    assertEq(_btcSpot, btcSpot);
  }

  /////////////
  // Helpers //
  /////////////

  function _submitMultipleTrades(uint from, uint to, Trade[] memory trades, bytes memory managerData) internal {
    IAccounts.AssetTransfer[] memory transfers = new IAccounts.AssetTransfer[](trades.length);
    for (uint i = 0; i < trades.length; i++) {
      transfers[i] = IAccounts.AssetTransfer({
        fromAcc: from,
        toAcc: to,
        asset: trades[i].asset,
        subId: trades[i].subId,
        amount: trades[i].amount,
        assetData: ""
      });
    }
    account.submitTransfers(transfers, managerData);
  }
}
