// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./TestStandardManagerBase.t.sol";
import {IBaseManager} from "../../../../src/interfaces/IBaseManager.sol";

/**
 * Focusing on the margin rules for options
 */
contract UNIT_TestStandardManager_MultiAsset is TestStandardManagerBase {
  function setUp() public override {
    super.setUp();
    manager.setWhitelistedCallee(address(ethFeed), true);
    manager.setWhitelistedCallee(address(btcFeed), true);

    // override perp MM to 0.1e18
    manager.setPerpMarginRequirements(ethMarketId, 0.05e18, 0.1e18);
    manager.setPerpMarginRequirements(btcMarketId, 0.05e18, 0.1e18);
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

  function testBaseAssetMarginDefaultToZero() public {
    // without setting discount factor, base asset contribute 0 to margin
    _deposit(wbtc, wbtcAsset, aliceAcc, 2e18);

    (int im, int mtm) = manager.getMarginAndMarkToMarket(aliceAcc, true, 1);
    assertEq(im, 0);
    assertEq(mtm, 40_000e18);
  }

  function testCannotSetInvalidBaseMarginFactor() public {
    vm.expectRevert(IStandardManager.SRM_InvalidBaseDiscountFactor.selector);
    manager.setBaseAssetMarginFactor(btcMarketId, 1.01e18, 1e18);
    vm.expectRevert(IStandardManager.SRM_InvalidBaseDiscountFactor.selector);
    manager.setBaseAssetMarginFactor(btcMarketId, 1e18, 1.01e18);
  }

  function testBaseAssetCanAddMargin() public {
    // enable a discount factor of 50%
    manager.setBaseAssetMarginFactor(btcMarketId, 0.5e18, 1e18);

    _deposit(wbtc, wbtcAsset, aliceAcc, 2e18);

    int im = manager.getMargin(aliceAcc, true);
    assertEq(im, int(btcSpot));
  }

  function testBaseAssetMarginWithContingency() public {
    manager.setOracleContingencyParams(
      btcMarketId, IStandardManager.OracleContingencyParams(0.5e18, 0.5e18, 0.5e18, 0.1e18)
    );
    // enable a discount factor of 50%
    manager.setBaseAssetMarginFactor(btcMarketId, 0.5e18, 1e18);
    btcFeed.setSpot(btcSpot, 0.3e18);

    _deposit(wbtc, wbtcAsset, aliceAcc, 2e18);

    // 2 * 20000 * 0.7 * 0.1 = 2800
    int expectedPenalty = 2800e18;

    int im = manager.getMargin(aliceAcc, true);
    assertEq(im, int(btcSpot) - expectedPenalty);

    // oracle contingency doesn't affect mm
    int mm = manager.getMargin(aliceAcc, false);
    assertEq(mm, int(btcSpot));
  }

  function testCanTradeBaseAsset() public {
    // mint and deposit some "weth asset token"
    _deposit(weth, wethAsset, aliceAcc, 10e18);

    (, int mtm) = manager.getMarginAndMarkToMarket(aliceAcc, true, 1);
    assertEq(mtm, int(ethSpot) * 10);

    // add 2 wbtc into the account!
    _deposit(wbtc, wbtcAsset, aliceAcc, 2e18);

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

  function testCanTradeMultiMarkets() public {
    uint dogeMarketId = manager.createMarket("doge");
    // Setup doge market
    MockOption dogeOption = new MockOption(subAccounts);
    MockFeeds dogeFeed = new MockFeeds();

    dogeFeed.setSpot(0.0005e18, 1e18);

    dogeFeed.setForwardPrice(expiry1, 0.0005e18, 1e18);

    manager.whitelistAsset(dogeOption, dogeMarketId, IStandardManager.AssetType.Option);

    manager.setOraclesForMarket(dogeMarketId, dogeFeed, dogeFeed, dogeFeed);

    IStandardManager.OptionMarginParams memory params =
      IStandardManager.OptionMarginParams(0.15e18, 0.1e18, 0.075e18, 0.075e18, 0.075e18, 1.4e18, 1.2e18, 1.05e18);
    manager.setOptionMarginParams(dogeMarketId, params);

    // summarize the initial margin for 2 options
    uint ethStrike = 2000e18;
    uint dogeStrike = 0.0006e18;

    (int ethMargin1,) = manager.getIsolatedMargin(ethMarketId, ethStrike, expiry1, true, -1e18, true);
    (int dogeMargin1,) = manager.getIsolatedMargin(dogeMarketId, dogeStrike, expiry1, true, -1000e18, true);

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

  function _deposit(MockERC20 token, MockAsset asset, uint account, uint amount) internal {
    token.mint(address(this), amount);
    token.approve(address(asset), amount);
    asset.deposit(account, 0, amount);
  }
}
