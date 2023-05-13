pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "src/risk-managers/BasicManager.sol";

import "lyra-utils/encoding/OptionEncoding.sol";

import "src/Accounts.sol";
import {IManager} from "src/interfaces/IManager.sol";
import {IAsset} from "src/interfaces/IAsset.sol";

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
contract UNIT_TestBasicManager_Option is Test {
  Accounts account;
  BasicManager manager;
  MockCash cash;
  MockERC20 usdc;
  MockPerp perp;
  MockOption option;
  MockOptionPricing pricing;
  uint expiry;

  MockFeeds feed;

  address alice = address(0xaa);
  address bob = address(0xbb);
  uint aliceAcc;
  uint bobAcc;

  function setUp() public {
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    usdc = new MockERC20("USDC", "USDC");

    cash = new MockCash(IERC20(usdc), account);

    perp = new MockPerp(account);

    option = new MockOption(account);

    feed = new MockFeeds();

    pricing = new MockOptionPricing();

    manager = new BasicManager(
      account,
      ICashAsset(address(cash))
    );

    manager.setPricingModule(pricing);

    manager.whitelistAsset(perp, 1, IBasicManager.AssetType.Perpetual);
    manager.whitelistAsset(option, 1, IBasicManager.AssetType.Option);

    manager.setOraclesForMarket(1, feed, feed, feed);

    aliceAcc = account.createAccountWithApproval(alice, address(this), manager);
    bobAcc = account.createAccountWithApproval(bob, address(this), manager);

    // set a future price that will be used for 90 day options
    expiry = block.timestamp + 91 days;
    feed.setSpot(1513e18, 1e18);

    usdc.mint(address(this), 100_000e18);
    usdc.approve(address(cash), type(uint).max);

    // set init perp trading parameters
    manager.setPerpMarginRequirements(1, 0.05e18, 0.1e18);

    IBasicManager.OptionMarginParameters memory params =
      IBasicManager.OptionMarginParameters(0.2e18, 0.1e18, 0.08e18, 0.125e18);

    manager.setOptionMarginParameters(1, params);
  }

  ////////////////
  //   Setter   //
  ////////////////

  function testWhitelistAsset() public {
    manager.whitelistAsset(perp, 2, IBasicManager.AssetType.Perpetual);
    manager.whitelistAsset(option, 2, IBasicManager.AssetType.Option);
    (bool isPerpWhitelisted, IBasicManager.AssetType perpType, uint8 marketId) = manager.assetDetails(perp);
    (bool isOptionWhitelisted, IBasicManager.AssetType optionType, uint8 optionMarketId) = manager.assetDetails(option);
    assertEq(isPerpWhitelisted, true);
    assertEq(uint(perpType), uint(IBasicManager.AssetType.Perpetual));
    assertEq(marketId, 2);

    assertEq(isOptionWhitelisted, true);
    assertEq(uint(optionType), uint(IBasicManager.AssetType.Option));
    assertEq(optionMarketId, 2);
  }

  function testSetOptionParameters() public {
    IBasicManager.OptionMarginParameters memory params =
      IBasicManager.OptionMarginParameters(0.5e18, 0.2e18, 0.1e18, 0.2e18);
    manager.setOptionMarginParameters(1, params);
    (int baselineOptionIM, int baselineOptionMM, int minStaticMMRatio, int minStaticIMRatio) =
      manager.optionMarginParams(1);
    assertEq(baselineOptionIM, 0.5e18);
    assertEq(baselineOptionMM, 0.2e18);
    assertEq(minStaticMMRatio, 0.1e18);
    assertEq(minStaticIMRatio, 0.2e18);
  }

  function testSetOracles() public {
    MockFeeds newFeed = new MockFeeds();
    manager.setOraclesForMarket(1, newFeed, newFeed, newFeed);
    assertEq(address(manager.spotFeeds(1)), address(newFeed));
    assertEq(address(manager.settlementFeeds(1)), address(newFeed));
    assertEq(address(manager.forwardFeeds(1)), address(newFeed));
  }

  ////////////////////////////////////////////////////
  // Isolated Margin Calculations For Naked Options //
  ////////////////////////////////////////////////////

  ///////////////
  // For Calls //
  ///////////////

  function testGetIsolatedMarginLongCall() public {
    int im = manager.getIsolatedMargin(1, 1000e18, expiry, true, 1e18, false);
    int mm = manager.getIsolatedMargin(1, 1000e18, expiry, true, 1e18, true);
    assertEq(im, 0);
    assertEq(mm, 0);
  }

  function testGetIsolatedMarginShortATMCall() public {
    uint strike = 1500e18;
    int im = manager.getIsolatedMargin(1, strike, expiry, true, -1e18, false);
    int mm = manager.getIsolatedMargin(1, strike, expiry, true, -1e18, true);
    assertEq(im / 1e18, -315);
    assertEq(mm / 1e18, -164);
  }

  function testGetIsolatedMarginShortITMCall() public {
    uint strike = 400e18;
    int im = manager.getIsolatedMargin(1, strike, expiry, true, -1e18, false);
    int mm = manager.getIsolatedMargin(1, strike, expiry, true, -1e18, true);
    assertEq(im / 1e18, -1415);
    assertEq(mm / 1e18, -1264);
  }

  function testGetIsolatedMarginShortOTMCall() public {
    uint strike = 3000e18;
    int im = manager.getIsolatedMargin(1, strike, expiry, true, -1e18, false);
    int mm = manager.getIsolatedMargin(1, strike, expiry, true, -1e18, true);
    assertEq(im / 1e18, -189);
    assertEq(mm / 1e18, -121);
  }

  //////////////
  // For Puts //
  //////////////

  function testGetIsolatedMarginLongPut() public {
    int im = manager.getIsolatedMargin(1, 1000e18, expiry, false, 1e18, false);
    int mm = manager.getIsolatedMargin(1, 1000e18, expiry, false, 1e18, true);
    assertEq(im, 0);
    assertEq(mm, 0);
  }

  function testGetIsolatedMarginShortATMPut() public {
    uint strike = 1500e18;
    int im = manager.getIsolatedMargin(1, strike, expiry, false, -1e18, false);
    int mm = manager.getIsolatedMargin(1, strike, expiry, false, -1e18, true);
    assertEq(im / 1e18, -289);
    assertEq(mm / 1e18, -138);
  }

  function testGetIsolatedMarginShortITMPut() public {
    uint strike = 3000e18;
    int im = manager.getIsolatedMargin(1, strike, expiry, false, -1e18, false);
    int mm = manager.getIsolatedMargin(1, strike, expiry, false, -1e18, true);
    assertEq(im / 1e18, -1789);
    assertEq(mm / 1e18, -1638);
  }

  function testGetIsolatedMarginShortOTMPut() public {
    uint strike = 400e18;
    int im = manager.getIsolatedMargin(1, strike, expiry, false, -1e18, false);
    int mm = manager.getIsolatedMargin(1, strike, expiry, false, -1e18, true);
    assertEq(im / 1e18, -189);
    assertEq(mm / 1e18, -121);
  }

  ////////////////////
  //  Margin Checks //
  ////////////////////

  function testCanTradeOptionWithEnoughMargin() public {
    uint strike = 2000e18;

    // alice short 1 2000-ETH CALL with 190 USDC as margin
    cash.deposit(aliceAcc, 190e18);
    _tradeOption(aliceAcc, bobAcc, 1e18, expiry, strike, true);
  }

  function testCanTradeSpreadWithMaxLoss() public {
    // Only require $100 to short call spread
    uint aliceShortLeg = 1500e18;
    uint aliceLongLeg = 1600e18;

    cash.deposit(aliceAcc, 100e18);
    _tradeSpread(aliceAcc, bobAcc, 1e18, 1e18, expiry, aliceShortLeg, aliceLongLeg, true);
  }

  function testDefaultToIsolatedMarginIfUnbounded() public {
    uint aliceShortLeg = 1500e18;
    uint aliceLongLeg = 1600e18;

    cash.deposit(aliceAcc, 100e18);
    // shorting 1 wei more than long, breaking max loss and default to isolated margin
    vm.expectRevert(
      abi.encodeWithSelector(IBasicManager.BM_PortfolioBelowMargin.selector, aliceAcc, 315_599999999999999100)
    );
    _tradeSpread(aliceAcc, bobAcc, 1e18 + 1, 1e18, expiry, aliceShortLeg, aliceLongLeg, true);
  }

  function testCanTradeZeroStrikeSpreadWithMaxLoss() public {
    uint aliceShortLeg = 0;
    uint aliceLongLeg = 400e18;
    cash.deposit(aliceAcc, 400e18);
    _tradeSpread(aliceAcc, bobAcc, 1e18, 1e18, expiry, aliceShortLeg, aliceLongLeg, true);
  }

  function testShortStraddle() public {
    uint strike = 1500e18;
    int amount = 1e18;

    int callMargin = manager.getIsolatedMargin(1, strike, expiry, true, -1e18, false);
    int putMargin = manager.getIsolatedMargin(1, strike, expiry, false, -1e18, false);

    // the margin needed is the sum of 2 positions
    cash.deposit(aliceAcc, uint(-(callMargin + putMargin)));

    IAccounts.AssetTransfer[] memory transfers = new IAccounts.AssetTransfer[](2);
    transfers[0] = IAccounts.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: option,
      subId: OptionEncoding.toSubId(expiry, strike, true),
      amount: amount,
      assetData: ""
    });
    transfers[1] = IAccounts.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: option,
      subId: OptionEncoding.toSubId(expiry, strike, false),
      amount: amount,
      assetData: ""
    });
    account.submitTransfers(transfers, "");
  }

  //////////////////////
  //    Settlement    //
  //////////////////////

  function testCanSettleOptions() public {
    uint strike = 2000e18;

    // alice short 10 2000-ETH CALL with 2000 USDC as margin
    cash.deposit(aliceAcc, 2000e18);
    _tradeOption(aliceAcc, bobAcc, 10e18, expiry, strike, true);

    int cashBefore = account.getBalance(aliceAcc, cash, 0);

    vm.warp(expiry + 1);
    uint subId = OptionEncoding.toSubId(expiry, strike, true);
    option.setMockedSubIdSettled(subId, true);
    option.setMockedTotalSettlementValue(subId, -500e18);

    manager.settleOptions(option, aliceAcc);

    int cashAfter = account.getBalance(aliceAcc, cash, 0);
    assertEq(cashBefore - cashAfter, 500e18);
  }

  function testCannotSettleWeirdAsset() public {
    MockOption badAsset = new MockOption(account);

    vm.warp(expiry + 1);
    feed.setSpot(2100e19, 1e18);
    vm.expectRevert(IBasicManager.BM_UnsupportedAsset.selector);
    manager.settleOptions(badAsset, aliceAcc);
  }

  /////////////
  // Helpers //
  /////////////

  function _tradeOption(uint fromAcc, uint toAcc, int amount, uint _expiry, uint strike, bool isCall) internal {
    IAccounts.AssetTransfer memory transfer = IAccounts.AssetTransfer({
      fromAcc: fromAcc,
      toAcc: toAcc,
      asset: option,
      subId: OptionEncoding.toSubId(_expiry, strike, isCall),
      amount: amount,
      assetData: ""
    });
    account.submitTransfer(transfer, "");
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
    IAccounts.AssetTransfer[] memory transfers = new IAccounts.AssetTransfer[](2);
    transfers[0] = IAccounts.AssetTransfer({
      fromAcc: fromAcc,
      toAcc: toAcc,
      asset: option,
      subId: OptionEncoding.toSubId(_expiry, strike1, isCall),
      amount: shortAmount,
      assetData: ""
    });
    transfers[1] = IAccounts.AssetTransfer({
      fromAcc: toAcc,
      toAcc: fromAcc,
      asset: option,
      subId: OptionEncoding.toSubId(_expiry, strike2, isCall),
      amount: longAmount,
      assetData: ""
    });
    account.submitTransfers(transfers, "");
  }

  function _getCashBalance(uint acc) public view returns (int) {
    return account.getBalance(acc, cash, 0);
  }
}
