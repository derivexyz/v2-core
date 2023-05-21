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

    // give Alice usdc, and give Bob coolToken
    mintAndDeposit(alice, aliceAcc, usdc, usdcAsset, 0, 10000000e18);
    mintAndDeposit(bob, bobAcc, coolToken, coolAsset, tokenSubId, 10000000e18);

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

    dutchAuction =
      dutchAuction = new DutchAuction(manager, account, ISecurityModule(address(0)), ICashAsset(address(0)));
  }

  function mintAndDeposit(
    address user,
    uint accountId,
    MockERC20 token,
    MockAsset assetWrapper,
    uint subId,
    uint amount
  ) public {
    token.mint(user, amount);

    vm.startPrank(user);
    token.approve(address(assetWrapper), type(uint).max);
    assetWrapper.deposit(accountId, subId, amount);
    vm.stopPrank();
  }

  ///////////
  // TESTS //
  ///////////

  function testSolventAuctionParams() public {
    // change params
    dutchAuction.setSolventAuctionParams(
      IDutchAuction.SolventAuctionParams({
        startingMtMPercentage: 0.98e18,
        fastAuctionLength: 300,
        slowAuctionLength: 3600,
        liquidatorFeeRate: 0.05e18
      })
    );

    // check if params changed
    (uint64 startingMtMPercentage, uint32 fastAuctionLength, uint32 slowAuctionLength, uint64 liquidatorFeeRate) =
      dutchAuction.solventAuctionParams();
    assertEq(startingMtMPercentage, 0.98e18);
    assertEq(fastAuctionLength, 300);
    assertEq(slowAuctionLength, 3600);
    assertEq(liquidatorFeeRate, 0.05e18);
  }

  function testCannotSetInvalidParams() public {
    vm.expectRevert(IDutchAuction.DA_InvalidParameter.selector);
    dutchAuction.setSolventAuctionParams(
      IDutchAuction.SolventAuctionParams({
        startingMtMPercentage: 1.02e18,
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

  function testGetRiskManager() public {
    assertEq(address(dutchAuction.riskManager()), address(manager));
  }
}
