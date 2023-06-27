pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "src/risk-managers/StandardManager.sol";
import "src/periphery/OptionSettlementHelper.sol";

import "lyra-utils/encoding/OptionEncoding.sol";

import "src/SubAccounts.sol";
import {IManager} from "src/interfaces/IManager.sol";
import {IAsset} from "src/interfaces/IAsset.sol";
import {IBaseManager} from "src/interfaces/IBaseManager.sol";
import {IDutchAuction} from "src/interfaces/IDutchAuction.sol";

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
contract UNIT_TestStandardManager_Option is Test {
  SubAccounts subAccounts;
  StandardManager manager;
  MockCash cash;
  MockERC20 usdc;
  MockPerp perp;
  MockOption option;
  MockOptionPricing pricing;
  OptionSettlementHelper optionHelper;
  uint expiry;

  uint8 ethMarketId = 1;

  MockFeeds feed;
  MockFeeds stableFeed;

  address alice = address(0xaa);
  address bob = address(0xbb);
  uint aliceAcc;
  uint bobAcc;

  uint feeRecipient;

  function setUp() public {
    subAccounts = new SubAccounts("Lyra Margin Accounts", "LyraMarginNFTs");

    usdc = new MockERC20("USDC", "USDC");

    cash = new MockCash(IERC20(usdc), subAccounts);

    perp = new MockPerp(subAccounts);

    option = new MockOption(subAccounts);

    feed = new MockFeeds();

    stableFeed = new MockFeeds();

    pricing = new MockOptionPricing();

    manager = new StandardManager(
      subAccounts,
      ICashAsset(address(cash)),
      IDutchAuction(address(0))
    );

    manager.setPricingModule(ethMarketId, pricing);

    manager.whitelistAsset(perp, ethMarketId, IStandardManager.AssetType.Perpetual);
    manager.whitelistAsset(option, ethMarketId, IStandardManager.AssetType.Option);

    manager.setOraclesForMarket(ethMarketId, feed, feed, feed, feed);

    aliceAcc = subAccounts.createAccountWithApproval(alice, address(this), manager);
    bobAcc = subAccounts.createAccountWithApproval(bob, address(this), manager);

    feeRecipient = subAccounts.createAccount(address(this), manager);

    // set a future price that will be used for 90 day options
    expiry = block.timestamp + 91 days;
    feed.setSpot(1500e18, 1e18);

    feed.setForwardPrice(expiry, 1500e18, 1e18);

    usdc.mint(address(this), 100_000e18);
    usdc.approve(address(cash), type(uint).max);

    feed.setVolConfidence(uint64(expiry), 1e18);

    // set init perp trading parameters
    manager.setPerpMarginRequirements(ethMarketId, 0.05e18, 0.1e18);

    IStandardManager.OptionMarginParams memory params =
      IStandardManager.OptionMarginParams(0.15e18, 0.1e18, 0.075e18, 0.075e18, 0.075e18, 1.4e18, 1.2e18, 1.05e18);

    manager.setOptionMarginParams(ethMarketId, params);

    manager.setStableFeed(stableFeed);
    stableFeed.setSpot(1e18, 1e18);
    manager.setDepegParameters(IStandardManager.DepegParams(0.98e18, 1.3e18));

    optionHelper = new OptionSettlementHelper();
  }

  ////////////////
  //   Setter   //
  ////////////////

  function testWhitelistAsset() public {
    manager.whitelistAsset(perp, 2, IStandardManager.AssetType.Perpetual);
    manager.whitelistAsset(option, 2, IStandardManager.AssetType.Option);

    IStandardManager.AssetDetail memory perpDetail = manager.assetDetails(perp);
    IStandardManager.AssetDetail memory optionDetail = manager.assetDetails(option);

    assertEq(perpDetail.isWhitelisted, true);
    assertEq(uint(perpDetail.assetType), uint(IStandardManager.AssetType.Perpetual));
    assertEq(perpDetail.marketId, 2);

    assertEq(optionDetail.isWhitelisted, true);
    assertEq(uint(optionDetail.assetType), uint(IStandardManager.AssetType.Option));
    assertEq(optionDetail.marketId, 2);
  }

  function testSetOptionParameters() public {
    IStandardManager.OptionMarginParams memory params =
      IStandardManager.OptionMarginParams(0.2e18, 0.15e18, 0.1e18, 0.07e18, 0.09e18, 1.4e18, 1.2e18, 1.05e18);
    manager.setOptionMarginParams(ethMarketId, params);
    (
      int maxSpotReq,
      int minSpotReq,
      int mmCallSpotReq,
      int mmPutSpotReq,
      int MMPutMtMReq,
      int unpairedIMScale,
      int unpairedMMScale,
      int mmOffsetScale
    ) = manager.optionMarginParams(ethMarketId);
    assertEq(maxSpotReq, 0.2e18);
    assertEq(minSpotReq, 0.15e18);
    assertEq(mmCallSpotReq, 0.1e18);
    assertEq(mmPutSpotReq, 0.07e18);
    assertEq(MMPutMtMReq, 0.09e18);
    assertEq(unpairedIMScale, 1.4e18);
    assertEq(unpairedMMScale, 1.2e18);
    assertEq(mmOffsetScale, 1.05e18);
  }

  function testSetOracles() public {
    MockFeeds newFeed = new MockFeeds();
    manager.setOraclesForMarket(ethMarketId, newFeed, newFeed, newFeed, newFeed);
    assertEq(address(manager.spotFeeds(1)), address(newFeed));
    assertEq(address(manager.settlementFeeds(1)), address(newFeed));
    assertEq(address(manager.forwardFeeds(1)), address(newFeed));
    assertEq(address(manager.volFeeds(1)), address(newFeed));
  }

  function testSetStableFeed() public {
    MockFeeds newFeed = new MockFeeds();
    manager.setStableFeed(newFeed);
    assertEq(address(manager.stableFeed()), address(newFeed));
  }

  function testSetDepegParameters() public {
    manager.setDepegParameters(IStandardManager.DepegParams(0.99e18, 1.2e18));
    (int threshold, int depegFactor) = manager.depegParams();
    assertEq(threshold, 0.99e18);
    assertEq(depegFactor, 1.2e18);
  }

  function testCannotSetInvalidDepegParameters() public {
    vm.expectRevert(IStandardManager.SRM_InvalidDepegParams.selector);
    manager.setDepegParameters(IStandardManager.DepegParams(1.01e18, 1.2e18));

    vm.expectRevert(IStandardManager.SRM_InvalidDepegParams.selector);
    manager.setDepegParameters(IStandardManager.DepegParams(0.9e18, 4e18));
  }

  function testSetOracleContingencyParams() public {
    manager.setOracleContingencyParams(
      ethMarketId, IStandardManager.OracleContingencyParams(0.8e18, 0.9e18, 0.7e18, 0.05e18)
    );

    (uint64 prepThreshold, uint64 optionThreshold, uint64 baseThreshold, int128 factor) =
      manager.oracleContingencyParams(ethMarketId);
    assertEq(prepThreshold, 0.8e18);
    assertEq(optionThreshold, 0.9e18);
    assertEq(baseThreshold, 0.7e18);
    assertEq(factor, 0.05e18);
  }

  function testCannotSetInvalidOracleContingencyParams() public {
    vm.expectRevert(IStandardManager.SRM_InvalidOracleContingencyParams.selector);
    manager.setOracleContingencyParams(
      ethMarketId, IStandardManager.OracleContingencyParams(1.01e18, 0.9e18, 0.8e18, 0.05e18)
    );

    vm.expectRevert(IStandardManager.SRM_InvalidOracleContingencyParams.selector);
    manager.setOracleContingencyParams(
      ethMarketId, IStandardManager.OracleContingencyParams(0.9e18, 1.01e18, 0.8e18, 0.05e18)
    );

    vm.expectRevert(IStandardManager.SRM_InvalidOracleContingencyParams.selector);
    manager.setOracleContingencyParams(
      ethMarketId, IStandardManager.OracleContingencyParams(0.9e18, 0.8e18, 1.01e18, 0.05e18)
    );

    vm.expectRevert(IStandardManager.SRM_InvalidOracleContingencyParams.selector);
    manager.setOracleContingencyParams(
      ethMarketId, IStandardManager.OracleContingencyParams(0.5e18, 0.9e18, 0.9e18, 1.2e18)
    );
  }

  ////////////////////////////////////////////////////
  // Isolated Margin Calculations For Naked Options //
  ////////////////////////////////////////////////////

  ///////////////
  // For Calls //
  ///////////////

  function testGetIsolatedMarginLongCall() public {
    (int im,) = manager.getIsolatedMargin(ethMarketId, 1000e18, expiry, true, 1e18, true);
    (int mm,) = manager.getIsolatedMargin(ethMarketId, 1000e18, expiry, true, 1e18, false);
    assertEq(im, 0);
    assertEq(mm, 0);
  }

  function testGetIsolatedMarginShortATMCall() public {
    uint strike = 1500e18;
    pricing.setMockMTM(strike, expiry, true, 100e18);

    (int im,) = manager.getIsolatedMargin(ethMarketId, strike, expiry, true, -1e18, true);
    (int mm,) = manager.getIsolatedMargin(ethMarketId, strike, expiry, true, -1e18, false);
    // (0.15 * 1500) + 100
    assertEq(im / 1e18, -325);
    // (0.075 * 1500) + 100
    assertEq(mm / 1e18, -212);
  }

  function testGetIsolatedMarginShortITMCall() public {
    uint strike = 400e18;
    pricing.setMockMTM(strike, expiry, true, 1100e18);

    (int im,) = manager.getIsolatedMargin(ethMarketId, strike, expiry, true, -1e18, true);
    (int mm,) = manager.getIsolatedMargin(ethMarketId, strike, expiry, true, -1e18, false);
    assertEq(im / 1e18, -1325);
    assertEq(mm / 1e18, -1212);
  }

  function testGetIsolatedMarginShortOTMCall() public {
    uint strike = 3000e18;
    pricing.setMockMTM(strike, expiry, true, 10e18);

    (int im,) = manager.getIsolatedMargin(ethMarketId, strike, expiry, true, -1e18, true);
    (int mm,) = manager.getIsolatedMargin(ethMarketId, strike, expiry, true, -1e18, false);
    assertEq(im / 1e18, -160);
    assertEq(mm / 1e18, -122);
  }

  //////////////
  // For Puts //
  //////////////

  function testGetIsolatedMarginLongPut() public {
    (int im,) = manager.getIsolatedMargin(ethMarketId, 1000e18, expiry, false, 1e18, true);
    (int mm,) = manager.getIsolatedMargin(ethMarketId, 1000e18, expiry, false, 1e18, false);
    assertEq(im, 0);
    assertEq(mm, 0);
  }

  function testGetIsolatedMarginShortATMPut() public {
    uint strike = 1500e18;
    pricing.setMockMTM(strike, expiry, false, 100e18);
    (int im,) = manager.getIsolatedMargin(ethMarketId, strike, expiry, false, -1e18, true);
    (int mm,) = manager.getIsolatedMargin(ethMarketId, strike, expiry, false, -1e18, false);
    // 0.15 * 1500 + 100 = 325
    assertEq(im / 1e18, -325);
    assertEq(mm / 1e18, -212);
  }

  function testGetIsolatedMarginShortITMPut() public {
    uint strike = 3000e18;
    pricing.setMockMTM(strike, expiry, false, 1500e18);
    (int im,) = manager.getIsolatedMargin(ethMarketId, strike, expiry, false, -1e18, true);
    (int mm,) = manager.getIsolatedMargin(ethMarketId, strike, expiry, false, -1e18, false);
    assertEq(im / 1e18, -1725);
    assertEq(mm / 1e18, -1612);
  }

  function testGetIsolatedMarginShortOTMPut() public {
    uint strike = 400e18;
    pricing.setMockMTM(strike, expiry, false, 10e18);
    (int im,) = manager.getIsolatedMargin(ethMarketId, strike, expiry, false, -1e18, true);
    (int mm,) = manager.getIsolatedMargin(ethMarketId, strike, expiry, false, -1e18, false);
    assertEq(im / 1e18, -160);
    assertEq(mm / 1e18, -122);
  }

  ////////////////////
  //  Margin Checks //
  ////////////////////

  function testCanTradeOptionWithEnoughMargin() public {
    uint strike = 2000e18;

    // alice short 1 2000-ETH CALL with 190 USDC as margin
    cash.deposit(aliceAcc, 190e18);
    _transferOption(aliceAcc, bobAcc, 1e18, expiry, strike, true);
  }

  function testCanTradeSpreadWithMaxLoss() public {
    // Only require $100 to short call spread
    uint aliceShortLeg = 1500e18;
    uint aliceLongLeg = 1600e18;

    cash.deposit(aliceAcc, 100e18);
    _tradeSpread(aliceAcc, bobAcc, 1e18, 1e18, expiry, aliceShortLeg, aliceLongLeg, true);
  }

  function testOIFeeOnOption() public {
    uint strike = 3000e18;
    uint subId = OptionEncoding.toSubId(expiry, 3000e18, true);

    manager.setOIFeeRateBPS(address(option), 0.001e18);
    manager.setFeeRecipient(feeRecipient);

    cash.deposit(aliceAcc, 300e18);

    uint tradeId = 2;
    option.setMockedOISnapshotBeforeTrade(subId, tradeId, 0);
    option.setMockedOI(subId, 100e18);

    // short 1 option
    _transferOption(aliceAcc, bobAcc, 1e18, expiry, strike, true);

    uint expectedFee = 1500 * 0.001e18;

    int cashAfter = _getCashBalance(aliceAcc);
    assertEq(uint(cashAfter), 300e18 - expectedFee);
  }

  function testBypassOIFee() public {
    uint strike = 3000e18;
    uint subId = OptionEncoding.toSubId(expiry, 3000e18, true);

    manager.setOIFeeRateBPS(address(option), 0.001e18);
    manager.setFeeRecipient(feeRecipient);
    manager.setFeeBypassedCaller(address(this), true);

    cash.deposit(aliceAcc, 300e18);

    uint tradeId = 2;
    option.setMockedOISnapshotBeforeTrade(subId, tradeId, 0);
    option.setMockedOI(subId, 100e18);

    // short 1 option
    _transferOption(aliceAcc, bobAcc, 1e18, expiry, strike, true);

    int cashAfter = _getCashBalance(aliceAcc);
    assertEq(uint(cashAfter), 300e18);
  }

  function testUnpairedLegsAreChargedInMargin() public {
    uint aliceShortLeg = 1500e18;
    uint aliceLongLeg = 1600e18;

    cash.deposit(aliceAcc, 123e18);
    // uint extraMargin =
    // shorting 0.01 wei more will require 22 USDC of option:
    // 1500 * 0.01 * 1.4 = 21
    // max loss 0.01 @ price 1600 = 1
    _tradeSpread(aliceAcc, bobAcc, 1.01e18, 1e18, expiry, aliceShortLeg, aliceLongLeg, true);
  }

  function testCanHoldExpiredOption() public {
    cash.deposit(aliceAcc, 400e18);

    uint strike = 2000e18;
    vm.warp(expiry + 1 hours);
    _transferOption(aliceAcc, bobAcc, 1e18, expiry, strike, true);
  }

  function testCanTradeZeroStrikeSpreadWithMaxLoss() public {
    uint aliceShortLeg = 0;
    uint aliceLongLeg = 400e18;
    cash.deposit(aliceAcc, 400e18);
    _tradeSpread(aliceAcc, bobAcc, 1e18, 1e18, expiry, aliceShortLeg, aliceLongLeg, true);
  }

  function testCannotTradeWithExpiryWithNoForwardPrice() public {
    uint strike = 2000e18;
    cash.deposit(aliceAcc, 190e18);

    vm.expectRevert(IStandardManager.SRM_NoForwardPrice.selector);
    _transferOption(aliceAcc, bobAcc, 1e18, expiry + 1, strike, true);
  }

  function testShortStraddle() public {
    uint strike = 1500e18;
    int amount = 1e18;

    (int callMargin,) = manager.getIsolatedMargin(ethMarketId, strike, expiry, true, -1e18, true);
    (int putMargin,) = manager.getIsolatedMargin(ethMarketId, strike, expiry, false, -1e18, true);

    // the margin needed is the sum of 2 positions
    cash.deposit(aliceAcc, uint(-(callMargin + putMargin)));

    ISubAccounts.AssetTransfer[] memory transfers = new ISubAccounts.AssetTransfer[](2);
    transfers[0] = ISubAccounts.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: option,
      subId: OptionEncoding.toSubId(expiry, strike, true),
      amount: amount,
      assetData: ""
    });
    transfers[1] = ISubAccounts.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: option,
      subId: OptionEncoding.toSubId(expiry, strike, false),
      amount: amount,
      assetData: ""
    });
    subAccounts.submitTransfers(transfers, "");
  }

  function testAllowRiskReducingTrade() public {
    uint strike = 2000e18;
    cash.deposit(aliceAcc, 2500e18);

    pricing.setMockMTM(strike, expiry, true, 100e18);
    _transferOption(aliceAcc, bobAcc, 10e18, expiry, strike, true);

    // assume that option price changes: now need more margin and the account is insolvent
    pricing.setMockMTM(strike, expiry, true, 300e18);

    // alice can still close position (pay premium), bob short, alice long,
    int closeAmount = 1e18;
    int premium = 100e18;
    // this trade can go through
    _tradeOption(bobAcc, aliceAcc, closeAmount, premium, expiry, strike, true);
  }

  function testOracleContingencyOnOptions() public {
    // set oracle contingency params
    manager.setOracleContingencyParams(
      ethMarketId, IStandardManager.OracleContingencyParams(0.8e18, 0.9e18, 0.8e18, 0.1e18)
    );

    // start a trade
    uint strike = 2000e18;
    pricing.setMockMTM(strike, expiry, true, 100e18);

    (int callMargin,) = manager.getIsolatedMargin(ethMarketId, strike, expiry, true, -10e18, true);
    cash.deposit(aliceAcc, uint(-callMargin));

    _transferOption(aliceAcc, bobAcc, 10e18, expiry, strike, true);

    (int imBefore, int mtmBefore) = manager.getMarginAndMarkToMarket(aliceAcc, true, 1);
    (int mmBefore,) = manager.getMarginAndMarkToMarket(aliceAcc, false, 1);
    assertEq(imBefore, 0);

    // update confidence in spot oracle to below threshold
    feed.setSpot(1500e18, 0.8e18);
    (int imAfter, int mtmAfter) = manager.getMarginAndMarkToMarket(aliceAcc, true, 1);
    (int mmAfter,) = manager.getMarginAndMarkToMarket(aliceAcc, false, 1);

    // expected im change: (1 - 0.8) * (1500) * 10 * 0.1 = -300
    assertEq(imAfter, -300e18);

    // mtm is not affected
    assertEq(mtmBefore, mtmAfter);
    // mm is not affected
    assertEq(mmBefore, mmAfter);
  }

  //////////////////////
  //    Settlement    //
  //////////////////////

  function testCanSettleOptions() public {
    uint strike = 2000e18;

    // alice short 10 2000-ETH CALL with 2000 USDC as margin
    cash.deposit(aliceAcc, 2000e18);
    _transferOption(aliceAcc, bobAcc, 10e18, expiry, strike, true);

    int cashBefore = subAccounts.getBalance(aliceAcc, cash, 0);

    vm.warp(expiry + 1);
    uint subId = OptionEncoding.toSubId(expiry, strike, true);
    option.setMockedSubIdSettled(subId, true);
    option.setMockedTotalSettlementValue(subId, -500e18);

    manager.settleOptions(option, aliceAcc);

    int cashAfter = subAccounts.getBalance(aliceAcc, cash, 0);
    assertEq(cashBefore - cashAfter, 500e18);
  }

  function testCannotSettleWeirdAsset() public {
    MockOption badAsset = new MockOption(subAccounts);

    vm.warp(expiry + 1);
    feed.setSpot(2100e19, 1e18);
    vm.expectRevert(IStandardManager.SRM_UnsupportedAsset.selector);
    manager.settleOptions(badAsset, aliceAcc);
  }

  function testSettleOptionWithManagerData() public {
    uint strike = 2000e18;
    cash.deposit(aliceAcc, 2000e18);
    _transferOption(aliceAcc, bobAcc, 10e18, expiry, strike, true);

    int cashBefore = subAccounts.getBalance(aliceAcc, cash, 0);

    vm.warp(expiry + 1);
    uint subId = OptionEncoding.toSubId(expiry, strike, true);
    option.setMockedSubIdSettled(subId, true);
    option.setMockedTotalSettlementValue(subId, -500e18);

    bytes memory data = abi.encode(address(manager), address(option), aliceAcc);
    IBaseManager.ManagerData[] memory allData = new IBaseManager.ManagerData[](1);
    allData[0] = IBaseManager.ManagerData({receiver: address(optionHelper), data: data});
    bytes memory managerData = abi.encode(allData);

    // only transfer 0 cash
    ISubAccounts.AssetTransfer memory transfer =
      ISubAccounts.AssetTransfer({fromAcc: aliceAcc, toAcc: bobAcc, asset: cash, subId: 0, amount: 0, assetData: ""});
    subAccounts.submitTransfer(transfer, managerData);

    int cashAfter = _getCashBalance(aliceAcc);
    assertEq(cashBefore - cashAfter, 500e18);
  }

  /////////////
  // Helpers //
  /////////////

  function _transferOption(uint fromAcc, uint toAcc, int amount, uint _expiry, uint strike, bool isCall) internal {
    ISubAccounts.AssetTransfer memory transfer = ISubAccounts.AssetTransfer({
      fromAcc: fromAcc,
      toAcc: toAcc,
      asset: option,
      subId: OptionEncoding.toSubId(_expiry, strike, isCall),
      amount: amount,
      assetData: ""
    });
    subAccounts.submitTransfer(transfer, "");
  }

  function _tradeOption(
    uint shortAcc,
    uint longAcc,
    int optionAmount,
    int premium,
    uint _expiry,
    uint strike,
    bool isCall
  ) internal {
    ISubAccounts.AssetTransfer[] memory transfers = new ISubAccounts.AssetTransfer[](2);
    transfers[0] = ISubAccounts.AssetTransfer({
      fromAcc: shortAcc,
      toAcc: longAcc,
      asset: option,
      subId: OptionEncoding.toSubId(_expiry, strike, isCall),
      amount: optionAmount,
      assetData: ""
    });
    transfers[1] = ISubAccounts.AssetTransfer({
      fromAcc: longAcc,
      toAcc: shortAcc,
      asset: cash,
      subId: 0,
      amount: premium,
      assetData: ""
    });
    subAccounts.submitTransfers(transfers, "");
  }

  function _tradeSpread(
    uint fromAcc,
    uint toAcc,
    int shortAmount,
    int longAmount,
    uint _expiry,
    uint strike1,
    uint strike2,
    bool isCall
  ) internal {
    ISubAccounts.AssetTransfer[] memory transfers = new ISubAccounts.AssetTransfer[](2);
    transfers[0] = ISubAccounts.AssetTransfer({
      fromAcc: fromAcc,
      toAcc: toAcc,
      asset: option,
      subId: OptionEncoding.toSubId(_expiry, strike1, isCall),
      amount: shortAmount,
      assetData: ""
    });
    transfers[1] = ISubAccounts.AssetTransfer({
      fromAcc: toAcc,
      toAcc: fromAcc,
      asset: option,
      subId: OptionEncoding.toSubId(_expiry, strike2, isCall),
      amount: longAmount,
      assetData: ""
    });
    subAccounts.submitTransfers(transfers, "");
  }

  function _getCashBalance(uint acc) public view returns (int) {
    return subAccounts.getBalance(acc, cash, 0);
  }
}
