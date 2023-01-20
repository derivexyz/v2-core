// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../src/liquidation/DutchAuction.sol";
import "../../src/Accounts.sol";
import "../shared/mocks/MockERC20.sol";
import "../shared/mocks/MockAsset.sol";

import "../../src/liquidation/DutchAuction.sol";

import "../shared/mocks/MockManager.sol";
import "../shared/mocks/MockFeed.sol";
import "../shared/mocks/MockIPCRM.sol";

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
  MockIPCRM manager;
  MockFeed feed;
  DutchAuction dutchAuction;
  DutchAuction.DutchAuctionParameters public dutchAuctionParameters;

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
    manager = new MockIPCRM(address(account));

    /*
     Feed for Spot*/
    feed = new MockFeed();
    feed.setSpot(1e18 * 1000); // setting feed to 1000 usdc per eth

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

  function testGetParams() public {
    DutchAuction.DutchAuctionParameters memory retParams = dutchAuction.getParameters();
    assertEq(retParams.stepInterval, dutchAuctionParameters.stepInterval);
    assertEq(retParams.lengthOfAuction, dutchAuctionParameters.lengthOfAuction);
    assertEq(retParams.securityModule, dutchAuctionParameters.securityModule);

    // change params
    dutchAuction.setDutchAuctionParameters(
      DutchAuction.DutchAuctionParameters({
        stepInterval: 2,
        lengthOfAuction: 200,
        securityModule: address(1),
        portfolioModifier: 1e18,
        inversePortfolioModifier: 1e18,
        secBetweenSteps: 0
      })
    );

    // check if params changed
    retParams = dutchAuction.getParameters();
    assertEq(retParams.stepInterval, 2);
    assertEq(retParams.lengthOfAuction, 200);
    assertEq(retParams.securityModule, address(1));
  }

  function testGetRiskManager() public {
    assertEq(address(dutchAuction.riskManager()), address(manager));
  }

  function testGetBounds() public {
    (int max, int min) = dutchAuction.getBounds(1);
    assertEq(max, 0);
    assertEq(min, 0);
  }
}
