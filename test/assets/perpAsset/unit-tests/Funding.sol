// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../../../../src/SubAccounts.sol";
import "../../../../src/assets/PerpAsset.sol";
import {ISubAccounts} from "../../../../src/interfaces/ISubAccounts.sol";
import {IPerpAsset} from "../../../../src/interfaces/IPerpAsset.sol";

import "../../../shared/mocks/MockManager.sol";
import "../../../shared/mocks/MockFeeds.sol";
import "../../../shared/mocks/MockSpotDiffFeed.sol";

contract UNIT_PerpAssetFunding is Test {
  PerpAsset perp;
  MockManager manager;
  SubAccounts subAccounts;
  MockFeeds spotFeed;
  MockSpotDiffFeed perpFeed;
  MockSpotDiffFeed askImpactFeed;
  MockSpotDiffFeed bidImpactFeed;

  // users
  address alice = address(0xaaaa);
  address bob = address(0xbbbb);
  // accounts
  uint aliceAcc;
  uint bobAcc;

  int defaultPosition = 1e18;
  int128 spot = 1500e18;

  function setUp() public {
    // deploy contracts
    subAccounts = new SubAccounts("Lyra", "LYRA");
    spotFeed = new MockFeeds();
    perpFeed = new MockSpotDiffFeed(spotFeed);
    askImpactFeed = new MockSpotDiffFeed(spotFeed);
    bidImpactFeed = new MockSpotDiffFeed(spotFeed);

    manager = new MockManager(address(subAccounts));
    perp = new PerpAsset(subAccounts, 0.0075e18);

    perp.setSpotFeed(spotFeed);
    perp.setPerpFeed(perpFeed);
    perp.setImpactFeeds(askImpactFeed, bidImpactFeed);

    manager = new MockManager(address(subAccounts));

    spotFeed.setSpot(uint(int(spot)), 1e18);

    perp.setWhitelistManager(address(manager), true);

    // create account for alice and bob
    aliceAcc = subAccounts.createAccountWithApproval(alice, address(this), manager);
    bobAcc = subAccounts.createAccountWithApproval(bob, address(this), manager);

    // open trades
    ISubAccounts.AssetTransfer memory transfer = ISubAccounts.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: perp,
      subId: 0,
      amount: defaultPosition,
      assetData: ""
    });
    subAccounts.submitTransfer(transfer, "");
  }

  function testSetSpotFeed() public {
    perp.setSpotFeed(ISpotFeed(address(0)));
    assertEq(address(perp.spotFeed()), address(0));
  }

  function testSetPerpFeed() public {
    perp.setPerpFeed(ISpotDiffFeed(address(0)));
    assertEq(address(perp.perpFeed()), address(0));
  }

  function testSetImpactPriceFeeds() public {
    perp.setImpactFeeds(ISpotDiffFeed(address(0)), ISpotDiffFeed(address(0)));
    assertEq(address(perp.impactBidPriceFeed()), address(0));
    assertEq(address(perp.impactAskPriceFeed()), address(0));
  }

  function testCannotSetSpotFeedFromNonOwner() public {
    vm.prank(alice);
    vm.expectRevert(bytes("Ownable: caller is not the owner"));
    perp.setSpotFeed(ISpotFeed(address(0)));
  }

  function testSetInterestRate() public {
    perp.setStaticInterestRate(0.000125e16); // 0.0125%
    assertEq(perp.staticInterestRate(), 0.000125e16);
  }

  function testCannotSetNegativeRate() public {
    vm.expectRevert(IPerpAsset.PA_InvalidStaticInterestRate.selector);
    perp.setStaticInterestRate(-0.000001e16);
  }

  function testSetImpactPrices() public {
    // set impact price
    bidImpactFeed.setSpotDiff(20e18, 1e18);
    askImpactFeed.setSpotDiff(40e18, 1e18);
    (uint bid, uint ask) = perp.getImpactPrices();
    assertEq(bid, 1520e18);
    assertEq(ask, 1540e18);
  }

  function testCannotGetFundingRateIfImpactPriceIsWrong() public {
    askImpactFeed.setSpotDiff(0e18, 1e18);
    bidImpactFeed.setSpotDiff(20e18, 1e18);

    vm.expectRevert(IPerpAsset.PA_InvalidImpactPrices.selector);
    perp.getFundingRate();
  }

  function testPositiveFundingRate() public {
    bidImpactFeed.setSpotDiff(6e18, 1e18);
    askImpactFeed.setSpotDiff(6e18, 1e18);

    assertEq(perp.getFundingRate(), 0.0005e18);
  }

  function testPositiveFundingRateCapped() public {
    bidImpactFeed.setSpotDiff(200e18, 1e18);
    askImpactFeed.setSpotDiff(200e18, 1e18);

    assertEq(perp.getFundingRate(), 0.0075e18);
  }

  function testNegativeFundingRate() public {
    bidImpactFeed.setSpotDiff(-6e18, 1e18);
    askImpactFeed.setSpotDiff(-6e18, 1e18);

    assertEq(perp.getFundingRate(), -0.0005e18);
  }

  function testNegativeFundingRateCapped() public {
    bidImpactFeed.setSpotDiff(-200e18, 1e18);
    askImpactFeed.setSpotDiff(-200e18, 1e18);

    assertEq(perp.getFundingRate(), -0.0075e18);
  }

  function testApplyZeroFundingNoTimeElapse() public {
    // apply funding
    perp.applyFundingOnAccount(aliceAcc);
    perp.applyFundingOnAccount(bobAcc);

    (, int funding,,,) = perp.positions(aliceAcc);

    assertEq(funding, 0);
  }

  // long pay short when mark > index
  function testApplyPositiveFunding() public {
    _setPricesPositiveFunding();

    vm.warp(block.timestamp + 1 hours);

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

  function testIndexPrice() public {
    spotFeed.setSpot(500e18, 1e18);
    (uint spotPrice,) = perp.getIndexPrice();
    assertEq(spotPrice, 500e18);

    perpFeed.setSpotDiff(50e18, 1e18);
    (uint perpPrice,) = perp.getPerpPrice();
    assertEq(perpPrice, 550e18);
  }

  function testSpotUpdateDoesNotBreakFunding() public {
    _setPricesPositiveFunding();

    vm.warp(block.timestamp + 1 hours);

    // applying alice and bob before and after spot update should not make sum inconsistent
    perp.applyFundingOnAccount(aliceAcc);

    // spot price update kicks in at this point
    spotFeed.setSpot(1000e18, 1e18);

    perp.applyFundingOnAccount(bobAcc);

    (, int aliceFunding,,,) = perp.positions(aliceAcc);
    (, int bobFunding,,,) = perp.positions(bobAcc);

    assertEq(aliceFunding, 0.75e18);
    assertEq(bobFunding, -0.75e18);
  }

  function testUnrealizedFundingShouldBeAccurate() public {
    _setPricesPositiveFunding();
    vm.warp(block.timestamp + 1 hours);

    // funding is not applied yet
    (, int aliceFunding,,,) = perp.positions(aliceAcc);
    assertEq(aliceFunding, 0);

    // estimated value should be updated
    int unrealized = perp.getUnsettledAndUnrealizedCash(aliceAcc);
    assertEq(unrealized, 0.75e18);

    // apply funding
    perp.applyFundingOnAccount(aliceAcc);
    int unrealized2 = perp.getUnsettledAndUnrealizedCash(aliceAcc);
    assertEq(unrealized2, 0.75e18); // same value, but got from positions.funding
  }

  function _setPricesPositiveFunding() internal {
    bidImpactFeed.setSpotDiff(6e18, 1e18);
    askImpactFeed.setSpotDiff(6e18, 1e18);
  }

  function _setPricesNegativeFunding() internal {
    bidImpactFeed.setSpotDiff(-6e18, 1e18);
    askImpactFeed.setSpotDiff(-6e18, 1e18);
  }
}
