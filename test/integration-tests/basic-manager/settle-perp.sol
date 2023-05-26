// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../../shared/mocks/MockManager.sol";
import "../../shared/mocks/MockFeeds.sol";
import "../../shared/mocks/MockERC20.sol";
import "../../assets/cashAsset/mocks/MockInterestRateModel.sol";

import "src/Accounts.sol";
import "src/risk-managers/StandardManager.sol";
import "src/assets/PerpAsset.sol";
import "src/assets/CashAsset.sol";
import "src/assets/Option.sol";
import {IAccounts} from "src/interfaces/IAccounts.sol";
import "src/interfaces/IPerpAsset.sol";

/**
 * This test use the real StandardManager & PerpAsset to test the settlement flow
 */
contract INTEGRATION_PerpAssetSettlement is Test {
  PerpAsset perp;
  Option option;
  StandardManager manager;
  CashAsset cash;
  Accounts account;
  MockFeeds feed;
  MockFeeds perpFeed;
  MockFeeds stableFeed;
  MockERC20 usdc;
  MockInterestRateModel rateModel;

  // keeper address to set impact prices
  address keeper = address(0xb0ba);
  // users
  address alice = address(0xaaaa);
  address bob = address(0xbbbb);
  address charlie = address(0xcccc);
  // accounts
  uint aliceAcc;
  uint bobAcc;
  uint charlieAcc;

  int oneContract = 1e18;

  uint initPrice = 1500e18;

  function setUp() public {
    // deploy contracts
    account = new Accounts("Lyra", "LYRA");
    feed = new MockFeeds();
    perpFeed = new MockFeeds();
    stableFeed = new MockFeeds();

    usdc = new MockERC20("USDC", "USDC");
    usdc.setDecimals(6);

    rateModel = new MockInterestRateModel(1e18);
    cash = new CashAsset(account, usdc, rateModel, 0, address(0));

    perp = new PerpAsset(account, 0.0075e18);

    perp.setSpotFeed(feed);
    perp.setPerpFeed(perpFeed);

    option = new Option(account, address(feed));

    manager = new StandardManager(account, ICashAsset(cash));

    manager.whitelistAsset(perp, 1, IStandardManager.AssetType.Perpetual);
    manager.whitelistAsset(option, 1, IStandardManager.AssetType.Option);

    manager.setOraclesForMarket(1, feed, feed, feed, feed, feed);

    manager.setStableFeed(stableFeed);
    stableFeed.setSpot(1e18, 1e18);
    manager.setDepegParameters(IStandardManager.DepegParams(0.98e18, 1.3e18));

    cash.setWhitelistManager(address(manager), true);

    perp.setWhitelistManager(address(manager), true);
    perp.setFundingRateOracle(keeper);

    // create account for alice, bob, charlie
    aliceAcc = account.createAccountWithApproval(alice, address(this), manager);
    bobAcc = account.createAccountWithApproval(bob, address(this), manager);
    charlieAcc = account.createAccountWithApproval(charlie, address(this), manager);

    _setPerpPrices(initPrice);

    usdc.mint(address(this), 120_000e6);
    usdc.approve(address(cash), 120_000e6);
    cash.deposit(aliceAcc, 40_000e6);
    cash.deposit(bobAcc, 40_000e6);
    cash.deposit(charlieAcc, 40_000e6);

    // open trades: Alice is Short, Bob is Long
    _tradePerpContract(aliceAcc, bobAcc, oneContract);
  }

  function testSettleLongPosition() public {
    int cashBefore = _getCashBalance(bobAcc);

    _setPerpPrices(1600e18);

    // bobAcc close his position and has $100 in PNL
    _tradePerpContract(bobAcc, aliceAcc, oneContract);

    int cashAfter = _getCashBalance(bobAcc);

    // bob has $100 in PNL
    assertEq(cashBefore + 100e18, cashAfter);
  }

  function testSettleShortPosition() public {
    int cashBefore = _getCashBalance(aliceAcc);

    // alice is short, bob is long
    _setPerpPrices(1600e18);

    // alice close his position and has $100 in PNL
    _tradePerpContract(bobAcc, aliceAcc, oneContract);

    int cashAfter = _getCashBalance(aliceAcc);

    // alice has lost $100
    assertEq(cashBefore - 100e18, cashAfter);
  }

  function testCanSettleUnrealizedLossForAnyAccount() public {
    int cashBefore = _getCashBalance(aliceAcc);

    // alice is short, bob is long
    _setPerpPrices(1600e18);

    manager.settlePerpsWithIndex(perp, aliceAcc);

    int cashAfter = _getCashBalance(aliceAcc);
    assertEq(cashBefore - 100e18, cashAfter);
  }

  function testCanSettleUnrealizedPNLForAnyAccount() public {
    int aliceCashBefore = _getCashBalance(aliceAcc);
    int bobCashBefore = _getCashBalance(bobAcc);

    // alice is short, bob is long
    _setPerpPrices(1600e18);

    manager.settlePerpsWithIndex(perp, aliceAcc);
    manager.settlePerpsWithIndex(perp, bobAcc);

    int aliceCashAfter = _getCashBalance(aliceAcc);
    int bobCashAfter = _getCashBalance(bobAcc);

    // alice loss $100
    assertEq(aliceCashBefore - 100e18, aliceCashAfter);

    // bob gets $100
    assertEq(bobCashBefore + 100e18, bobCashAfter);
  }

  function testCanSettleIntoNegativeCash() public {
    _setPerpPrices(200_000e18);
    manager.settlePerpsWithIndex(perp, aliceAcc);
    assertLt(_getCashBalance(aliceAcc), 0);
  }

  function _setPerpPrices(uint price) internal {
    perpFeed.setSpot(price, 1e18);
  }

  function _getEntryPriceAndPNL(uint acc) internal view returns (uint, int) {
    (uint entryPrice,, int pnl,,) = perp.positions(acc);
    return (entryPrice, pnl);
  }

  function _tradePerpContract(uint fromAcc, uint toAcc, int amount) internal {
    IAccounts.AssetTransfer memory transfer =
      IAccounts.AssetTransfer({fromAcc: fromAcc, toAcc: toAcc, asset: perp, subId: 0, amount: amount, assetData: ""});
    account.submitTransfer(transfer, "");
  }

  function _getCashBalance(uint acc) public view returns (int) {
    return account.getBalance(acc, cash, 0);
  }
}
