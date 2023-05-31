pragma solidity ^0.8.13;

import "./TestStandardManagerBase.t.sol";

/**
 * Focusing on the margin rules for options
 */
contract UNIT_TestStandardManager_MultiAsset is TestStandardManagerBase {
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
    MockOption dogeOption = new MockOption(subAccounts);
    MockFeeds dogeFeed = new MockFeeds();
    MockOptionPricing pricing = new MockOptionPricing();

    dogeFeed.setSpot(0.0005e18, 1e18);

    dogeFeed.setForwardPrice(expiry1, 0.0005e18, 1e18);

    manager.whitelistAsset(dogeOption, 5, IStandardManager.AssetType.Option);
    manager.setOraclesForMarket(5, dogeFeed, dogeFeed, dogeFeed, dogeFeed, dogeFeed);

    manager.setPricingModule(5, pricing);

    IStandardManager.OptionMarginParameters memory params =
      IStandardManager.OptionMarginParameters(0.15e18, 0.1e18, 0.075e18, 0.075e18, 0.075e18, 1.4e18, 1.2e18, 1.05e18);
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
}
