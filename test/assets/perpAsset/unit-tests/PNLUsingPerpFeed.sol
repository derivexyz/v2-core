// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../../../shared/mocks/MockManager.sol";
import "../../../shared/mocks/MockFeeds.sol";

import "src/Accounts.sol";
import "src/assets/PerpAsset.sol";
import {IAccounts} from "src/interfaces/IAccounts.sol";
import "src/interfaces/IPerpAsset.sol";

contract UNIT_PerpAssetPNL is Test {
  PerpAsset perp;
  MockManager manager;
  Accounts account;
  MockFeeds feed;

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
    manager = new MockManager(address(account));
    perp = new PerpAsset(IAccounts(account), 0.0075e18);

    perp.setSpotFeed(feed);
    perp.setPerpFeed(feed);

    perp.setWhitelistManager(address(manager), true);
    perp.setFundingRateOracle(keeper);

    // create account for alice, bob, charlie
    aliceAcc = account.createAccountWithApproval(alice, address(this), manager);
    bobAcc = account.createAccountWithApproval(bob, address(this), manager);
    charlieAcc = account.createAccountWithApproval(charlie, address(this), manager);

    feed.setSpot(initPrice, 1e18);

    // open trades: Alice is Short, Bob is Long
    _tradePerpContract(aliceAcc, bobAcc, oneContract);
  }

  function testInitState_spotDiff() public {
    // alice is short, bob is long
    int alicePnl = _getPNL(aliceAcc);
    int bobPnl = _getPNL(bobAcc);

    assertEq(alicePnl, 0);
    assertEq(bobPnl, 0);

    assertEq(perp.getUnsettledAndUnrealizedCash(aliceAcc), 0);
    assertEq(perp.getUnsettledAndUnrealizedCash(bobAcc), 0);
  }

  /* -------------------------- */
  /* Test Long position on Bob  */
  /* -------------------------- */

  function testCanRealizeProfitForAnyone_spotDiff() public {
    // price increase, in favor of Bob's position
    _setPrices(1600e18);

    perp.realizePNLWithIndex(bobAcc);

    int pnl = _getPNL(bobAcc);
    assertEq(pnl, 100e18);
  }

  function testCanRealizeLossesForAnyone_spotDiff() public {
    // price increase, in favor of Bob's position
    _setPrices(1400e18);

    perp.realizePNLWithIndex(bobAcc);

    int pnl = _getPNL(bobAcc);
    assertEq(pnl, -100e18);
  }

  function testIncreaseLongPosition_spotDiff() public {
    // price increase, in favor of Bob's position
    _setPrices(1600e18);

    // bob has $100 in unrealized PNL
    assertEq(perp.getUnsettledAndUnrealizedCash(bobAcc), 100e18);

    // bob trade with charlie to increase long position
    _tradePerpContract(charlieAcc, bobAcc, oneContract);

    int pnl = _getPNL(bobAcc);
    assertEq(pnl, 100e18);
  }

  function testCloseLongPositionWithProfit_spotDiff() public {
    // price increase, in favor of Bob's position
    _setPrices(1600e18);

    assertEq(perp.getUnsettledAndUnrealizedCash(bobAcc), 100e18);

    // bob trade with charlie to completely close his long position
    _tradePerpContract(bobAcc, charlieAcc, oneContract);

    int pnl = _getPNL(bobAcc);
    assertEq(pnl, 100e18);

    assertEq(perp.getUnsettledAndUnrealizedCash(bobAcc), 100e18);
  }

  function testCloseLongPositionWithLosses_spotDiff() public {
    // price decrease, against of Bob's position
    _setPrices(1400e18);

    assertEq(perp.getUnsettledAndUnrealizedCash(bobAcc), -100e18);

    // bob trade with charlie to completely close his long position
    _tradePerpContract(bobAcc, charlieAcc, oneContract);

    int pnl = _getPNL(bobAcc);
    assertEq(pnl, -100e18);
  }

  function testPartialCloseLongPositionWithProfit_spotDiff() public {
    // price increase, in favor of Bob's position
    _setPrices(1600e18);

    // bob trade with charlie to close half of his long position
    _tradePerpContract(bobAcc, charlieAcc, oneContract / 2);

    int pnl = _getPNL(bobAcc);
    assertEq(pnl, 100e18);

    assertEq(perp.getUnsettledAndUnrealizedCash(bobAcc), 100e18);
  }

  function testPartialCloseLongPositionWithLosses_spotDiff() public {
    // price decrease, against of Bob's position
    _setPrices(1400e18);

    // bob trade with charlie to close half of his long position
    _tradePerpContract(bobAcc, charlieAcc, oneContract / 2);

    int pnl = _getPNL(bobAcc);
    assertEq(pnl, -100e18);

    assertEq(perp.getUnsettledAndUnrealizedCash(bobAcc), -100e18);
  }

  function testFromLongToShort_spotDiff() public {
    // price decrease, against of Bob's position
    _setPrices(1400e18);

    // bob trade with charlie to close his long position
    // + and open a short position
    _tradePerpContract(bobAcc, charlieAcc, 2 * oneContract);

    int pnl = _getPNL(bobAcc);
    assertEq(pnl, -100e18); // loss is realized

    assertEq(perp.getUnsettledAndUnrealizedCash(bobAcc), -100e18);
  }

  /* ------------------------------ */
  /*  Test Short position on Alice  */
  /* ------------------------------ */

  function testIncreaseShortPosition_spotDiff() public {
    // price increase, again alice's position
    _setPrices(1600e18);

    // alice trade with charlie to increase short position
    _tradePerpContract(aliceAcc, charlieAcc, oneContract);

    int pnl = _getPNL(aliceAcc);
    assertEq(pnl, -100e18);

    // unrealized loss
    assertEq(perp.getUnsettledAndUnrealizedCash(aliceAcc), -100e18);
  }

  function testCloseShortPositionWithProfit_spotDiff() public {
    // price decrease, in favor of alice's position
    _setPrices(1400e18);

    // alice trade with charlie to completely close her short position
    _tradePerpContract(charlieAcc, aliceAcc, oneContract);

    int pnl = _getPNL(aliceAcc);
    assertEq(pnl, 100e18);

    assertEq(perp.getUnsettledAndUnrealizedCash(aliceAcc), 100e18);
  }

  function testCloseShortPositionWithLosses_spotDiff() public {
    // price increase, against of alice's position
    _setPrices(1600e18);

    // alice trade with charlie to completely close her short position
    _tradePerpContract(charlieAcc, aliceAcc, oneContract);

    int pnl = _getPNL(aliceAcc);
    assertEq(pnl, -100e18);

    assertEq(perp.getUnsettledAndUnrealizedCash(aliceAcc), -100e18);
  }

  function testPartialCloseShortPositionWithProfit_spotDiff() public {
    // price decrease, in favor of alice's position
    _setPrices(1400e18);

    // alice trade with charlie to close half of her short position
    _tradePerpContract(charlieAcc, aliceAcc, oneContract / 2);

    int pnl = _getPNL(aliceAcc);
    assertEq(pnl, 100e18);

    assertEq(perp.getUnsettledAndUnrealizedCash(aliceAcc), 100e18);
  }

  function testPartialCloseShortPositionWithLosses_spotDiff() public {
    // price increase, against of alice's position
    _setPrices(1600e18);

    // alice trade with charlie to close half of her short position
    _tradePerpContract(charlieAcc, aliceAcc, oneContract / 2);

    // pnl of the whole old position is updated to position.PNL
    int pnl = _getPNL(aliceAcc);
    assertEq(pnl, -100e18);

    assertEq(perp.getUnsettledAndUnrealizedCash(aliceAcc), -100e18);
  }

  function testFromShortToLong_spotDiff() public {
    // price increase, against of alice's position
    _setPrices(1600e18);

    // alice trade with charlie to close her short position
    // + and open a long position
    _tradePerpContract(charlieAcc, aliceAcc, 2 * oneContract);

    int pnl = _getPNL(aliceAcc);
    assertEq(pnl, -100e18); // loss is realized
  }

  /* ------------------ */
  /*   Test settlement  */
  /* ------------------ */

  function testCannotSettleWithArbitraryAccount_spotDiff() public {
    vm.expectRevert(IPerpAsset.PA_WrongManager.selector);
    perp.settleRealizedPNLAndFunding(bobAcc);
  }

  function testMockSettleBob_spotDiff() public {
    // price decrease, against of Bob's position
    _setPrices(1400e18);

    // bob trade with charlie to completely close his long position
    _tradePerpContract(bobAcc, charlieAcc, oneContract);
    assertEq(perp.getUnsettledAndUnrealizedCash(bobAcc), -100e18);

    // mock settle
    vm.prank(address(manager));
    perp.settleRealizedPNLAndFunding(bobAcc);
    assertEq(perp.getUnsettledAndUnrealizedCash(bobAcc), 0);
  }

  function testMockSettleAlice_spotDiff() public {
    // price decreased, in favor of alice's position
    _setPrices(1400e18);

    // alice trade with charlie to completely close her short position
    _tradePerpContract(charlieAcc, aliceAcc, oneContract);
    assertEq(perp.getUnsettledAndUnrealizedCash(aliceAcc), 100e18);

    // mock settle
    vm.prank(address(manager));
    perp.settleRealizedPNLAndFunding(aliceAcc);
    assertEq(perp.getUnsettledAndUnrealizedCash(aliceAcc), 0);
  }

  function testRevertsWithTooLowSpotDiff() public {
    feed.setSpotDiff(-2000e18, 1e18);
    // a negative value will revert
    vm.expectRevert(IPerpAsset.PA_InvalidIndexPrice.selector);
    perp.getIndexPrice();

    feed.setSpotDiff(-int128(int(initPrice)), 1e18);
    // but 0 is allowed
    assertEq(perp.getIndexPrice(), 0);
  }

  function _setPrices(uint price) internal {
    feed.setSpotDiff(int128(int(price) - int(initPrice)), 1e18);
  }

  function _getPNL(uint acc) internal view returns (int) {
    (,, int pnl,,) = perp.positions(acc);
    return pnl;
  }

  function _tradePerpContract(uint fromAcc, uint toAcc, int amount) internal {
    IAccounts.AssetTransfer memory transfer =
      IAccounts.AssetTransfer({fromAcc: fromAcc, toAcc: toAcc, asset: perp, subId: 0, amount: amount, assetData: ""});
    account.submitTransfer(transfer, "");
  }
}
