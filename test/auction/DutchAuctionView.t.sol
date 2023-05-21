// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "src/liquidation/DutchAuction.sol";
import "src/Accounts.sol";

// shared mocks
import "../shared/mocks/MockERC20.sol";
import "../shared/mocks/MockAsset.sol";

import "../shared/mocks/MockManager.sol";
import "../shared/mocks/MockFeeds.sol";

// local mocks

import "./mocks/MockLiquidatableManager.sol";

contract UNIT_DutchAuctionView is Test {
  address alice;
  address bob;

  uint aliceAcc;
  uint bobAcc;
  uint expiry;
  Accounts account;
  MockERC20 usdc;
  MockERC20 coolToken;
  MockAsset usdcAsset;
  MockAsset optionAdapter;
  MockAsset coolAsset;
  MockLiquidatableManager manager;
  MockFeeds feed;

  DutchAuction dutchAuction;
  IDutchAuction.SolventAuctionParams public dutchAuctionParameters;

  uint tokenSubId = 1000;

  function setUp() public {
    vm.warp(10 days);
    deployMockSystem();
    setupAccounts();
  }

  function setupAccounts() public {
    alice = address(0xaa);
    bob = address(0xbb);
    usdc.approve(address(usdcAsset), type(uint).max);
    // usdcAsset.deposit(ownAcc, 0, 100_000_000e18);
    aliceAcc = account.createAccount(alice, manager);
    bobAcc = account.createAccount(bob, manager);

    coolToken = new MockERC20("Cool", "COOL");
    coolAsset = new MockAsset(IERC20(coolToken), account, false);

    expiry = block.timestamp + 1 days;
  }

  /// @dev deploy mock system
  function deployMockSystem() public {
    /* Base Layer */
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    /* Wrappers */
    usdc = new MockERC20("usdc", "USDC");

    // usdc asset: deposit with usdc, cannot be negative
    usdcAsset = new MockAsset(IERC20(usdc), account, false);
    usdcAsset = new MockAsset(IERC20(usdc), account, false);

    // optionAsset: not allow deposit, can be negative
    optionAdapter = new MockAsset(IERC20(address(0)), account, true);

    /* Risk Manager */
    manager = new MockLiquidatableManager(address(account));

    /*
    Feed for Spot*/
    feed = new MockFeeds();
    feed.setSpot(1e18 * 1000, 1e18); // setting feed to 1000 usdc per eth

    dutchAuction = new DutchAuction(account, ISecurityModule(address(0)), ICashAsset(address(0)));

    dutchAuction.setSolventAuctionParams(_getDefaultSolventParams());
  }

  ///////////
  // TESTS //
  ///////////

  function testSolventAuctionParams() public {
    // change params
    dutchAuction.setSolventAuctionParams(
      IDutchAuction.SolventAuctionParams({
        startingMtMPercentage: 0.98e18,
        fastAuctionCutoffPercentage: 0.8e18,
        fastAuctionLength: 300,
        slowAuctionLength: 3600,
        liquidatorFeeRate: 0.05e18
      })
    );

    // check if params changed
    (
      uint64 startingMtMPercentage,
      uint64 cutoff,
      uint32 fastAuctionLength,
      uint32 slowAuctionLength,
      uint64 liquidatorFeeRate
    ) = dutchAuction.solventAuctionParams();
    assertEq(startingMtMPercentage, 0.98e18);
    assertEq(cutoff, 0.8e18);
    assertEq(fastAuctionLength, 300);
    assertEq(slowAuctionLength, 3600);
    assertEq(liquidatorFeeRate, 0.05e18);
  }

  function testCannotSetInvalidParams() public {
    vm.expectRevert(IDutchAuction.DA_InvalidParameter.selector);
    dutchAuction.setSolventAuctionParams(
      IDutchAuction.SolventAuctionParams({
        startingMtMPercentage: 1.02e18,
        fastAuctionCutoffPercentage: 0.8e18,
        fastAuctionLength: 300,
        slowAuctionLength: 3600,
        liquidatorFeeRate: 0.05e18
      })
    );

    vm.expectRevert(IDutchAuction.DA_InvalidParameter.selector);
    dutchAuction.setSolventAuctionParams(
      IDutchAuction.SolventAuctionParams({
        startingMtMPercentage: 0.9e18,
        fastAuctionCutoffPercentage: 0.91e18,
        fastAuctionLength: 300,
        slowAuctionLength: 3600,
        liquidatorFeeRate: 0.05e18
      })
    );
  }

  function testSetInsolventAuctionParameters() public {
    dutchAuction.setInsolventAuctionParams(IDutchAuction.InsolventAuctionParams({totalSteps: 100, coolDown: 2}));

    // expect value
    (uint32 totalSteps, uint32 coolDown) = dutchAuction.insolventAuctionParams();
    assertEq(totalSteps, 100);
    assertEq(coolDown, 2);
  }

  function testGetDiscountPercentage() public {
    // default setting: fast auction 100% - 80% (600second), slow auction 80% - 0% (7200 secs)

    // auction starts!
    uint startTime = block.timestamp;

    // fast forward 300 seconds
    vm.warp(block.timestamp + 300);

    (uint discount, bool isFast) = dutchAuction.getDiscountPercentage(startTime, block.timestamp);
    assertEq(discount, 0.9e18);
    assertTrue(isFast);

    // fast forward 300 seconds, 600 seconds into the auction
    vm.warp(block.timestamp + 300);
    (discount, isFast) = dutchAuction.getDiscountPercentage(startTime, block.timestamp);
    assertEq(discount, 0.8e18);
    assertTrue(!isFast);

    // fast forward 360 seconds, 960 seconds into the auction
    vm.warp(block.timestamp + 360);
    (discount, isFast) = dutchAuction.getDiscountPercentage(startTime, block.timestamp);
    assertEq(discount, 0.76e18);
    assertTrue(!isFast);

    // fast forward 7200 seconds, everything ends
    vm.warp(block.timestamp + 7200);
    (discount, isFast) = dutchAuction.getDiscountPercentage(startTime, block.timestamp);
    assertEq(discount, 0);
    assertTrue(!isFast);
  }

  function testGetDiscountPercentage2() public {
    // new setting: fast auction 96% - 80%, slow auction 80% - 0%
    IDutchAuction.SolventAuctionParams memory params = _getDefaultSolventParams();
    params.startingMtMPercentage = 0.96e18;
    params.fastAuctionCutoffPercentage = 0.8e18;
    params.fastAuctionLength = 300;

    dutchAuction.setSolventAuctionParams(params);

    // auction starts!
    uint startTime = block.timestamp;

    (uint discount, bool isFast) = dutchAuction.getDiscountPercentage(startTime, block.timestamp);
    assertEq(discount, 0.96e18);
    assertTrue(isFast);

    // fast forward 150 seconds, half of fast auction
    vm.warp(block.timestamp + 150);
    (discount,) = dutchAuction.getDiscountPercentage(startTime, block.timestamp);
    assertEq(discount, 0.88e18);

    // another 150 seconds
    vm.warp(block.timestamp + 150);
    (discount,) = dutchAuction.getDiscountPercentage(startTime, block.timestamp);
    assertEq(discount, 0.8e18);

    // pass 90% of slow auction
    vm.warp(block.timestamp + 6480);
    (discount,) = dutchAuction.getDiscountPercentage(startTime, block.timestamp);
    assertEq(discount, 0.08e18);
  }

  function testGetMaxProportion() public {}

  //////////////////////////
  ///       Helpers      ///
  //////////////////////////

  function _getDefaultSolventParams() internal view returns (IDutchAuction.SolventAuctionParams memory) {
    return IDutchAuction.SolventAuctionParams({
      startingMtMPercentage: 1e18,
      fastAuctionCutoffPercentage: 0.8e18,
      fastAuctionLength: 600,
      slowAuctionLength: 7200,
      liquidatorFeeRate: 0
    });
  }
}
