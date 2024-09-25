// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../../../shared/mocks/MockManager.sol";
import "../../../shared/mocks/MockFeeds.sol";

import "../../../../src/SubAccounts.sol";
import "../../../../src/assets/PerpAsset.sol";
import {ISubAccounts} from "../../../../src/interfaces/ISubAccounts.sol";
import {IPerpAsset} from "../../../../src/interfaces/IPerpAsset.sol";
import "../../../shared/mocks/MockSpotDiffFeed.sol";

contract UNIT_PerpAssetMigration is Test {
  PerpAsset perp;
  MockManager manager;
  SubAccounts subAccounts;
  MockFeeds spotFeed;
  MockSpotDiffFeed perpFeed;

  MockSpotDiffFeed iap;
  MockSpotDiffFeed ibp;

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
    subAccounts = new SubAccounts("Lyra", "LYRA");

    spotFeed = new MockFeeds();
    spotFeed.setSpot(initPrice, 1e18);

    perpFeed = new MockSpotDiffFeed(spotFeed);

    iap = new MockSpotDiffFeed(spotFeed);
    ibp = new MockSpotDiffFeed(spotFeed);

    manager = new MockManager(address(subAccounts));
    perp = new PerpAsset(subAccounts);
    perp.setRateBounds(0.0075e18);

    perp.setSpotFeed(spotFeed);
    perp.setPerpFeed(perpFeed);
    perp.setImpactFeeds(iap, ibp);

    perp.setWhitelistManager(address(manager), true);

    // create account for alice, bob, charlie
    aliceAcc = subAccounts.createAccountWithApproval(alice, address(this), manager);
    bobAcc = subAccounts.createAccountWithApproval(bob, address(this), manager);
    charlieAcc = subAccounts.createAccountWithApproval(charlie, address(this), manager);

    _setMarkPrices(initPrice);

    // open trades: Alice is Short, Bob is Long
    _tradePerpContract(aliceAcc, bobAcc, oneContract);
  }

  /* ------------------------------ */
  /*  Test Short position on Alice  */
  /* ------------------------------ */

  function testIncreaseShortPosition() public {
    // price increase, again alice's position
    _setMarkPrices(1600e18);

    // alice trade with charlie to increase short position
    _tradePerpContract(aliceAcc, charlieAcc, oneContract);

    int pnl = _getPNL(aliceAcc);
    assertEq(pnl, -100e18);
    assertEq(perp.getUnsettledAndUnrealizedCash(aliceAcc), -100e18);

    perp.disable();
    _setMarkPrices(8888e18);

    // unrealized loss
    assertEq(perp.getUnsettledAndUnrealizedCash(aliceAcc), -100e18);
  }

  function testCloseShortPositionWithProfit() public {
    // price decrease, in favor of alice's position
    _setMarkPrices(1400e18);

    // alice trade with charlie to completely close her short position
    _tradePerpContract(charlieAcc, aliceAcc, oneContract);

    perp.disable();
    _setMarkPrices(8888e18);

    int pnl = _getPNL(aliceAcc);
    assertEq(pnl, 100e18);

    assertEq(perp.getUnsettledAndUnrealizedCash(aliceAcc), 100e18);
  }

  function testCloseShortPositionWithLosses() public {
    // price increase, against of alice's position
    _setMarkPrices(1600e18);

    // alice trade with charlie to completely close her short position
    _tradePerpContract(charlieAcc, aliceAcc, oneContract);

    perp.disable();
    _setMarkPrices(8888e18);

    int pnl = _getPNL(aliceAcc);
    assertEq(pnl, -100e18);

    assertEq(perp.getUnsettledAndUnrealizedCash(aliceAcc), -100e18);
  }

  function testPartialCloseShortPositionWithProfit() public {
    // price decrease, in favor of alice's position
    _setMarkPrices(1400e18);

    // alice trade with charlie to close half of her short position
    _tradePerpContract(charlieAcc, aliceAcc, oneContract / 2);

    perp.disable();
    _setMarkPrices(8888e18);

    int pnl = _getPNL(aliceAcc);
    assertEq(pnl, 100e18);

    assertEq(perp.getUnsettledAndUnrealizedCash(aliceAcc), 100e18);
  }

  function testPartialCloseShortPositionWithLosses() public {
    // price increase, against of alice's position
    _setMarkPrices(1600e18);

    // alice trade with charlie to close half of her short position
    _tradePerpContract(charlieAcc, aliceAcc, oneContract / 2);

    perp.disable();
    _setMarkPrices(8888e18);

    // pnl of the whole old position is updated to position.PNL
    int pnl = _getPNL(aliceAcc);
    assertEq(pnl, -100e18);

    assertEq(perp.getUnsettledAndUnrealizedCash(aliceAcc), -100e18);
  }

  function testFromShortToLong() public {
    // price increase, against of alice's position
    _setMarkPrices(1600e18);

    // alice trade with charlie to close her short position
    // + and open a long position
    _tradePerpContract(charlieAcc, aliceAcc, 2 * oneContract);

    perp.disable();
    _setMarkPrices(8888e18);

    int pnl = _getPNL(aliceAcc);
    assertEq(pnl, -100e18); // loss is realized
  }

  // Test Funding

  /* ------------------ */
  /*   Test settlement  */
  /* ------------------ */

  function testMockSettleBob() public {
    // price decrease, against of Bob's position
    _setMarkPrices(1400e18);

    // bob trade with charlie to completely close his long position
    _tradePerpContract(bobAcc, charlieAcc, oneContract);
    assertEq(perp.getUnsettledAndUnrealizedCash(bobAcc), -100e18);

    perp.disable();
    _setMarkPrices(8888e18);

    // Once disabled, even after the mark price changes, the unsettled value is unchanged
    assertEq(perp.getUnsettledAndUnrealizedCash(bobAcc), -100e18);

    vm.prank(address(manager));
    perp.settleRealizedPNLAndFunding(bobAcc);

    assertEq(perp.getUnsettledAndUnrealizedCash(bobAcc), 0);
    assertEq(subAccounts.getBalance(bobAcc, perp, 0), 0);
  }

  function testMockSettleAlice() public {
    // price decreased, in favor of alice's position
    _setMarkPrices(1400e18);

    // alice trade with charlie to completely close her short position
    _tradePerpContract(charlieAcc, aliceAcc, oneContract);
    assertEq(subAccounts.getBalance(aliceAcc, perp, 0), 0);
    assertEq(perp.getUnsettledAndUnrealizedCash(aliceAcc), 100e18);

    perp.disable();
    _setMarkPrices(8888e18);

    // mock settle
    vm.prank(address(manager));
    perp.settleRealizedPNLAndFunding(aliceAcc);
    assertEq(perp.getUnsettledAndUnrealizedCash(aliceAcc), 0);
    assertEq(subAccounts.getBalance(aliceAcc, perp, 0), 0);
  }

  function testMockSettleWithOpenBalance() public {
    perp.disable();
    
    // mock settle
    vm.prank(address(manager));
    perp.settleRealizedPNLAndFunding(aliceAcc);
    vm.prank(address(manager));
    perp.settleRealizedPNLAndFunding(bobAcc);
    vm.prank(address(manager));
    perp.settleRealizedPNLAndFunding(charlieAcc);

    assertEq(subAccounts.getBalance(aliceAcc, perp, 0), 0);
    assertEq(subAccounts.getBalance(bobAcc, perp, 0), 0);
    assertEq(subAccounts.getBalance(charlieAcc, perp, 0), 0);
  }

  function testFeedFreezing() public {
    ibp.setSpotDiff(100e18, 1e18);
    iap.setSpotDiff(120e18, 1e18);
    assertGt(perp.getFundingRate(), 0);

    _setMarkPrices(1600e18);
    (uint perpPrice,) = perp.getPerpPrice();
    assertEq(perpPrice, 1600e18);

    perp.disable();
    assertEq(perp.getFundingRate(), 0);
    assertTrue(perp.isDisabled());

    (perpPrice,) = perp.getPerpPrice();
    assertEq(perpPrice, 1600e18);
    assertEq(perp.frozenPerpPrice(), 1600e18);

    _setMarkPrices(4000e18);

    // Price doesn't change after the perp is disabled
    (perpPrice,) = perp.getPerpPrice();
    assertEq(perpPrice, 1600e18);
  }

  function _setMarkPrices(uint price) internal {
    (uint spot,) = spotFeed.getSpot();
    perpFeed.setSpotDiff(int(price) - int(spot), 1e18);
  }

  function _getPNL(uint acc) internal view returns (int) {
    (,, int pnl,,) = perp.positions(acc);
    return pnl;
  }

  function _tradePerpContract(uint fromAcc, uint toAcc, int amount) internal {
    ISubAccounts.AssetTransfer memory transfer =
      ISubAccounts.AssetTransfer({fromAcc: fromAcc, toAcc: toAcc, asset: perp, subId: 0, amount: amount, assetData: ""});
    subAccounts.submitTransfer(transfer, "");
  }
}
