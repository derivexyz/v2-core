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

  // keeper address to set impact prices
  address keeper = address(0xb0ba);
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
    perp = new PerpAsset(IAccounts(account), 0.0075e18);

    perp.setSpotFeed(feed);

    // whitelist keepers
    perp.setWhitelistManager(address(manager), true);
    perp.setImpactPriceOracle(keeper);

    // create account for alice and bob
    aliceAcc = account.createAccountWithApproval(alice, address(this), manager);
    bobAcc = account.createAccountWithApproval(bob, address(this), manager);

    _setPricesPositiveFunding();

    // open trades
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

  function testSetSpotFeed() public {
    perp.setSpotFeed(IChainlinkSpotFeed(address(0)));
    assertEq(address(perp.spotFeed()), address(0));
  }

  function testCannotSetSpotFeedFromNonOwner() public {
    vm.prank(alice);
    vm.expectRevert(AbstractOwned.OnlyOwner.selector);
    perp.setSpotFeed(IChainlinkSpotFeed(address(0)));
  }

  function testUnWhitelistBot() public {
    perp.setImpactPriceOracle(address(this));
    vm.prank(keeper);
    vm.expectRevert(IPerpAsset.PA_OnlyImpactPriceOracle.selector);
    perp.setPremium(1e18);
  }

  function testSetPremium() public {
    // set premium price
    vm.prank(keeper);

    perp.setPremium(2e18);
    assertEq(perp.premium(), 2e18);
  }

  function testSetInterestRate() public {
    perp.setStaticInterestRate(0.000125e16); // 0.0125%
    assertEq(perp.staticInterestRate(), 0.000125e16);
  }

  function testCannotSetNegativeRate() public {
    vm.expectRevert(IPerpAsset.PA_InvalidStaticInterestRate.selector);
    perp.setStaticInterestRate(-0.000001e16);
  }

  function testPositiveFundingRate() public {
    _setPricesPositiveFunding();

    // this number * index = funding per 1 contract
    assertEq(perp.getFundingRate(), 0.0005e18);
  }

  function testPositiveFundingRateCapped() public {
    vm.prank(keeper);
    perp.setPremium(5e18);

    assertEq(perp.getFundingRate(), 0.0075e18);
  }

  function testNegativeFundingRate() public {
    _setPricesNegativeFunding();

    // this number * index = funding per 1 contract
    assertEq(perp.getFundingRate(), -0.0005e18);
  }

  function testNegativeFundingRateCapped() public {
    vm.prank(keeper);
    perp.setPremium(-1e18);

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

  function _setPricesPositiveFunding() internal {
    uint spot = 1500e18;

    // expected premium: 6 / 8 = 0.75

    feed.setSpot(spot);

    vm.prank(keeper);
    perp.setPremium(0.004e18);
  }

  function _setPricesNegativeFunding() internal {
    uint spot = 1500e18;
    feed.setSpot(spot);

    vm.prank(keeper);
    perp.setPremium(-0.004e18);
  }
}
