// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../../../shared/mocks/MockManager.sol";
import "../../../shared/mocks/MockFeed.sol";

import "src/Accounts.sol";
import "src/assets/PerpAsset.sol";
import "src/interfaces/IAccounts.sol";
import "src/interfaces/IPerpAsset.sol";

contract UNIT_PerpAssetFunding is Test {
  PerpAsset perp;
  MockManager manager;
  Accounts account;
  MockFeed feed;

  // bot address to set impact prices
  address bot = address(0xb0ba);
  // users
  address alice = address(0xaaaa);
  address bob = address(0xbbbb);
  // accounts
  uint aliceAcc;
  uint bobAcc;

  int defaultPosition = 1e18;

  function setUp() public {
    // deploy contracts
    account = new Accounts("Lyra", "LYRA");
    feed = new MockFeed();
    manager = new MockManager(address(account));
    perp = new PerpAsset(IAccounts(account), feed);

    // whitelist bots
    perp.setWhitelistManager(address(manager), true);
    perp.setWhitelistBot(bot, true);

    // create account for alice and bob
    aliceAcc = account.createAccount(alice, manager);
    bobAcc = account.createAccount(bob, manager);

    _setPricesPositiveFunding();

    // open trades
    vm.prank(alice);
    AccountStructs.AssetTransfer memory transfer = AccountStructs.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: perp,
      subId: 0,
      amount: defaultPosition,
      assetData: ""
    });
    account.submitTransfer(transfer, "");
  }

  function testCannotSetNegativeImpactPrices() public {
    vm.prank(bot);
    vm.expectRevert(IPerpAsset.PA_ImpactPriceMustBePositive.selector);
    perp.setImpactPrices(-1, 1);
  }

  function testCannotSetAskPriceLowerThanAskBid() public {
    vm.prank(bot);
    vm.expectRevert(IPerpAsset.PA_InvalidImpactPrices.selector);
    perp.setImpactPrices(1, 2);
  }

  function testUnWhitelistBot() public {
    perp.setWhitelistBot(bot, false);
    vm.prank(bot);
    vm.expectRevert(IPerpAsset.PA_OnlyBot.selector);
    perp.setImpactPrices(1540e18, 1520e18);
  }

  function testSetImpactPrices() public {
    // set impact price
    vm.prank(bot);
    perp.setImpactPrices(1540e18, 1520e18);
    assertEq(perp.impactAskPrice(), 1540e18);
    assertEq(perp.impactBidPrice(), 1520e18);
  }

  function testPositiveFundingRate() public {
    _setPricesPositiveFunding();

    // this number * index = funding per 1 contract
    assertEq(perp.getFundingRate(), 0.0005e18);
  }

  function testPositiveFundingRateCapped() public {
    int iap = 1601e18;
    int ibp = 1600e18;

    vm.prank(bot);
    perp.setImpactPrices(iap, ibp);

    assertEq(perp.getFundingRate(), 0.0075e18);
  }

  function testNegativeFundingRate() public {
    _setPricesNegativeFunding();

    // this number * index = funding per 1 contract
    assertEq(perp.getFundingRate(), -0.0005e18);
  }

  function testNegativeFundingRateCapped() public {
    int iap = 1401e18;
    int ibp = 1400e18;

    vm.prank(bot);
    perp.setImpactPrices(iap, ibp);

    assertEq(perp.getFundingRate(), -0.0075e18);
  }

  function testApplyZeroFundingNoTimeElapse() public {
    // apply funding
    perp.updateFundingRate();
    perp.applyFundingOnAccount(aliceAcc);
    perp.applyFundingOnAccount(bobAcc);

    (, int funding,,,) = perp.positions(aliceAcc);

    assertEq(funding, 0);
  }

  // long pay short when mark > index
  function testApplyPositiveFunding() public {
    vm.warp(block.timestamp + 1 hours);
    // apply funding
    perp.updateFundingRate();

    // alice is short, bob is long
    perp.applyFundingOnAccount(aliceAcc);
    perp.applyFundingOnAccount(bobAcc);

    // alice received funding
    (, int aliceFunding,,,) = perp.positions(aliceAcc);

    // bob paid funding
    (, int bobFunding,,,) = perp.positions(bobAcc);

    assertEq(aliceFunding, 0.75e18);
    assertEq(bobFunding, -0.75e18);
  }

  // short pay long when mark < index
  function testApplyNegativeFunding() public {
    _setPricesNegativeFunding();

    vm.warp(block.timestamp + 1 hours);
    // apply funding
    perp.updateFundingRate();

    // alice is short, bob is long
    perp.applyFundingOnAccount(aliceAcc);
    perp.applyFundingOnAccount(bobAcc);

    // alice paid funding
    (, int aliceFunding,,,) = perp.positions(aliceAcc);

    // bob received funding
    (, int bobFunding,,,) = perp.positions(bobAcc);

    assertEq(aliceFunding, -0.75e18);
    assertEq(bobFunding, 0.75e18);
  }

  function _setPricesPositiveFunding() internal returns (uint, int, int) {
    uint spot = 1500e18;
    int iap = 1512e18;
    int ibp = 1506e18;

    // expected premium: 6 / 8 = 0.75

    feed.setSpot(spot);

    vm.prank(bot);
    perp.setImpactPrices(iap, ibp);
    return (spot, iap, ibp);
  }

  function _setPricesNegativeFunding() internal returns (uint, int, int) {
    uint spot = 1500e18;
    int iap = 1494e18;
    int ibp = 1488e18;

    // expected premium -6 / 8 = -0.75

    feed.setSpot(spot);
    vm.prank(bot);
    perp.setImpactPrices(iap, ibp);
    return (spot, iap, ibp);
  }
}
