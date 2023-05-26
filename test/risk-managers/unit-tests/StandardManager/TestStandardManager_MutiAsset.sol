pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "src/risk-managers/StandardManager.sol";

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
import "test/shared/mocks/MockAsset.sol";
import "test/auction/mocks/MockCashAsset.sol";

/**
 * Focusing on the margin rules for options
 */
contract UNIT_TestStandardManager_MultiAsset is Test {
  Accounts account;
  StandardManager manager;
  MockCash cash;
  MockERC20 usdc;
  MockERC20 weth;
  MockERC20 wbtc;

  MockPerp ethPerp;
  MockPerp btcPerp;
  MockOption ethOption;
  MockOption btcOption;
  // mocked base asset!
  MockAsset wethAsset;
  MockAsset wbtcAsset;

  MockOptionPricing btcPricing;
  MockOptionPricing ethPricing;

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

    stableFeed = new MockFeeds();

    // Setup asset for ETH Markets
    ethPerp = new MockPerp(account);
    ethOption = new MockOption(account);
    ethFeed = new MockFeeds();

    // setup asset for BTC Markets
    btcPerp = new MockPerp(account);
    btcOption = new MockOption(account);

    // setup mock base asset (only change mark to market)
    weth = new MockERC20("weth", "weth");
    wethAsset = new MockAsset(weth, account, false); // false as it cannot go negative
    wbtc = new MockERC20("wbtc", "wbtc");
    wbtcAsset = new MockAsset(wbtc, account, false); // false as it cannot go negative

    btcFeed = new MockFeeds();

    ethPricing = new MockOptionPricing();
    btcPricing = new MockOptionPricing();

    manager = new StandardManager(
      account,
      ICashAsset(address(cash))
    );

    manager.setPricingModule(ethMarketId, ethPricing);
    manager.setPricingModule(btcMarketId, btcPricing);

    manager.whitelistAsset(ethPerp, ethMarketId, IStandardManager.AssetType.Perpetual);
    manager.whitelistAsset(ethOption, ethMarketId, IStandardManager.AssetType.Option);
    manager.whitelistAsset(wethAsset, ethMarketId, IStandardManager.AssetType.Base);
    manager.setOraclesForMarket(ethMarketId, ethFeed, ethFeed, ethFeed, ethFeed, ethFeed);

    manager.whitelistAsset(btcPerp, btcMarketId, IStandardManager.AssetType.Perpetual);
    manager.whitelistAsset(btcOption, btcMarketId, IStandardManager.AssetType.Option);
    manager.whitelistAsset(wbtcAsset, btcMarketId, IStandardManager.AssetType.Base);
    manager.setOraclesForMarket(btcMarketId, btcFeed, btcFeed, btcFeed, btcFeed, btcFeed);

    manager.setStableFeed(stableFeed);
    stableFeed.setSpot(1e18, 1e18);
    manager.setDepegParameters(IStandardManager.DepegParams(0.98e18, 1.3e18));

    aliceAcc = account.createAccountWithApproval(alice, address(this), manager);
    bobAcc = account.createAccountWithApproval(bob, address(this), manager);

    expiry1 = block.timestamp + 7 days;
    expiry2 = block.timestamp + 14 days;
    expiry3 = block.timestamp + 30 days;

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
    manager.setPerpMarginRequirements(ethMarketId, 0.05e18, 0.1e18);
    manager.setPerpMarginRequirements(btcMarketId, 0.05e18, 0.1e18);

    IStandardManager.OptionMarginParameters memory params =
      IStandardManager.OptionMarginParameters(0.15e18, 0.1e18, 0.075e18, 0.075e18, 0.075e18, 1.4e18);

    manager.setOptionMarginParameters(ethMarketId, params);
    manager.setOptionMarginParameters(btcMarketId, params);
  }

  function testCanTradeMultipleMarkets() public {
    // summarize the initial margin for 2 options
    uint ethStrike = 2000e18;
    uint btcStrike = 30000e18;
    (int ethMargin,) = manager.getIsolatedMargin(ethMarketId, ethStrike, expiry1, true, -1e18, true);
    (int btcMargin,) = manager.getIsolatedMargin(btcMarketId, btcStrike, expiry1, true, -1e18, true);

    int neededMargin = ethMargin + btcMargin;
    cash.deposit(aliceAcc, uint(-neededMargin));

    // short 1 eth call + 1 btc call
    Trade[] memory trades = new Trade[](2);
    trades[0] = Trade(ethOption, 1e18, OptionEncoding.toSubId(expiry1, ethStrike, true));
    trades[1] = Trade(btcOption, 1e18, OptionEncoding.toSubId(expiry1, btcStrike, true));
    _submitMultipleTrades(aliceAcc, bobAcc, trades, "");

    int im = manager.getMargin(aliceAcc, true);
    assertEq(im, 0);
  }

  function testCanTradeMultiMarketMultiExpiry() public {
    // summarize the initial margin for 2 options
    uint ethStrike = 2000e18;
    uint btcStrike = 30000e18;
    (int ethMargin1,) = manager.getIsolatedMargin(ethMarketId, ethStrike, expiry1, true, -1e18, true);
    (int btcMargin1,) = manager.getIsolatedMargin(btcMarketId, btcStrike, expiry1, true, -1e18, true);
    (int ethMargin2,) = manager.getIsolatedMargin(ethMarketId, ethStrike, expiry2, true, -1e18, true);
    (int btcMargin2,) = manager.getIsolatedMargin(btcMarketId, btcStrike, expiry2, true, -1e18, true);

    int neededMargin = ethMargin1 + btcMargin1 + ethMargin2 + btcMargin2;
    cash.deposit(aliceAcc, uint(-neededMargin));

    Trade[] memory trades = new Trade[](4);
    trades[0] = Trade(ethOption, 1e18, OptionEncoding.toSubId(expiry1, ethStrike, true));
    trades[1] = Trade(btcOption, 1e18, OptionEncoding.toSubId(expiry1, btcStrike, true));
    trades[2] = Trade(ethOption, 1e18, OptionEncoding.toSubId(expiry2, ethStrike, true));
    trades[3] = Trade(btcOption, 1e18, OptionEncoding.toSubId(expiry2, btcStrike, true));

    // short 1 eth call + 1 btc call
    _submitMultipleTrades(aliceAcc, bobAcc, trades, "");

    int im = manager.getMargin(aliceAcc, true);

    // well collateralized
    assertEq(im, 0);
  }

  function testCanTradeMultiMarketOptionPerps() public {
    // summarize the initial margin for 2 options
    uint ethStrike = 2000e18;
    uint btcStrike = 30000e18;
    (int ethMargin1,) = manager.getIsolatedMargin(ethMarketId, ethStrike, expiry1, true, -1e18, true);
    (int btcMargin1,) = manager.getIsolatedMargin(btcMarketId, btcStrike, expiry1, true, -1e18, true);
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

    int im = manager.getMargin(aliceAcc, true); // account, im, trusted(not used)
    assertEq(im, 0);
  }

  function testCanTradeBaseAsset() public {
    // mint and deposit some "weth asset token"
    uint amount = 10e18;
    weth.mint(address(this), amount);
    weth.approve(address(wethAsset), amount);
    wethAsset.deposit(aliceAcc, 0, amount);

    (int im, int mtm) = manager.getMarginAndMarkToMarket(aliceAcc, true, 1);
    assertEq(im, 0); // doesn't contribute to margin
    assertEq(mtm, int(ethSpot) * 10);

    // add 2 wbtc into the account!
    uint btcAmount = 2e18;
    wbtc.mint(address(this), btcAmount);
    wbtc.approve(address(wbtcAsset), btcAmount);
    wbtcAsset.deposit(aliceAcc, 0, btcAmount);

    // mark to market now include wbtc value!
    (, int newMtm) = manager.getMarginAndMarkToMarket(aliceAcc, true, 1);
    assertEq(newMtm, int(ethSpot) * 10 + int(btcSpot) * 2);
  }

  function testMultiMarketDepeg() public {
    // summarize the initial margin for 2 options
    uint ethStrike = 2000e18;
    uint btcStrike = 30000e18;
    (int ethMargin1,) = manager.getIsolatedMargin(ethMarketId, ethStrike, expiry1, true, -1e18, true);
    (int btcMargin1,) = manager.getIsolatedMargin(btcMarketId, btcStrike, expiry1, true, -1e18, true);
    int ethPerpMargin = -150e18;
    int btcPerpMargin = -2000e18;

    // USDC depeg to 0.95
    // 1 short eth option + 1 eth perp position => 1.3 x eth spot x 2 * 0.03  = 117
    // 1 short btc option + 1 btc perp position => 1.3 x btc x 2 * 0.03  = 1560
    stableFeed.setSpot(0.95e18, 1e18);

    int depegMargin = -(117e18 + 1560e18);
    int neededMargin = ethMargin1 + btcMargin1 + ethPerpMargin + btcPerpMargin + depegMargin;

    cash.deposit(aliceAcc, uint(-neededMargin));
    cash.deposit(bobAcc, uint(-neededMargin));

    Trade[] memory trades = new Trade[](4);
    trades[0] = Trade(ethOption, 1e18, OptionEncoding.toSubId(expiry1, ethStrike, true));
    trades[1] = Trade(btcOption, 1e18, OptionEncoding.toSubId(expiry1, btcStrike, true));
    trades[2] = Trade(ethPerp, 1e18, 0);
    trades[3] = Trade(btcPerp, 1e18, 0);

    // short 1 eth call + 1 btc call
    _submitMultipleTrades(aliceAcc, bobAcc, trades, "");

    int im = manager.getMargin(aliceAcc, true);
    assertEq(im, 0);
  }

  function testCanTradeMultiMarketsNotInOrder() public {
    // Setup doge market
    MockOption dogeOption = new MockOption(account);
    MockFeeds dogeFeed = new MockFeeds();
    MockOptionPricing pricing = new MockOptionPricing();

    dogeFeed.setSpot(0.0005e18, 1e18);

    dogeFeed.setForwardPrice(expiry1, 0.0005e18, 1e18);

    manager.whitelistAsset(dogeOption, 5, IStandardManager.AssetType.Option);
    manager.setOraclesForMarket(5, dogeFeed, dogeFeed, dogeFeed, dogeFeed, dogeFeed);

    manager.setPricingModule(5, pricing);

    IStandardManager.OptionMarginParameters memory params =
      IStandardManager.OptionMarginParameters(0.15e18, 0.1e18, 0.075e18, 0.075e18, 0.075e18, 1.4e18);
    manager.setOptionMarginParameters(5, params);

    // summarize the initial margin for 2 options
    uint ethStrike = 2000e18;
    uint dogeStrike = 0.0006e18;
    pricing.setMockMTM(dogeStrike, expiry1, true, 0.0005e18);
    ethPricing.setMockMTM(ethStrike, expiry1, true, 100e18);

    (int ethMargin1,) = manager.getIsolatedMargin(ethMarketId, ethStrike, expiry1, true, -1e18, true);
    (int dogeMargin1,) = manager.getIsolatedMargin(5, dogeStrike, expiry1, true, -1000e18, true);

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

    int im = manager.getMargin(aliceAcc, true);

    assertEq(im, 0);
  }

  function testPassMultipleManagerData() public {
    cash.deposit(aliceAcc, 10000e18);

    // oracle data
    uint newEthSpot = 2100e18;
    uint newBtcSpot = 30100e18;
    IBaseManager.ManagerData[] memory oracleData = new IBaseManager.ManagerData[](2);
    oracleData[0] = IBaseManager.ManagerData({receiver: address(ethFeed), data: abi.encode(newEthSpot)});
    oracleData[1] = IBaseManager.ManagerData({receiver: address(btcFeed), data: abi.encode(newBtcSpot)});
    bytes memory managerData = abi.encode(oracleData);

    // build trades
    uint strike = 2500e18;
    Trade[] memory trades = new Trade[](1);
    trades[0] = Trade(ethOption, 1e18, OptionEncoding.toSubId(expiry1, strike, true));

    _submitMultipleTrades(aliceAcc, bobAcc, trades, managerData);

    (uint _ethSpot,) = ethFeed.getSpot();
    (uint _btcSpot,) = btcFeed.getSpot();
    assertEq(_ethSpot, newEthSpot);
    assertEq(_btcSpot, newBtcSpot);
  }

  function testCanTransferCash() public {
    int amount = 1000e18;

    cash.deposit(aliceAcc, uint(amount));

    IAccounts.AssetTransfer memory transfer =
      IAccounts.AssetTransfer({fromAcc: aliceAcc, toAcc: bobAcc, asset: cash, subId: 0, amount: amount, assetData: ""});

    account.submitTransfer(transfer, "");
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
