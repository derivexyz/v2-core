pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "test/feeds/mocks/MockV3Aggregator.sol";
import "src/feeds/ChainlinkSpotFeeds.sol";
import "src/assets/Option.sol";
import "src/risk-managers/PCRM.sol";
import "src/Account.sol";
import "src/interfaces/IManager.sol";
import "src/interfaces/IAsset.sol";
import "src/interfaces/AccountStructs.sol";
import "test/shared/mocks/MockManager.sol";
import "test/risk-managers/mocks/MockDutchAuction.sol";

contract UNIT_TestPCRM is Test {
  Account account;
  PCRM manager;

  ChainlinkSpotFeeds spotFeeds; //todo: should replace with generic mock
  MockV3Aggregator aggregator;
  Option option;
  MockDutchAuction auction;

  address alice = address(0xaa);
  address bob = address(0xbb);
  uint aliceAcc;
  uint bobAcc;

  function setUp() public {
    account = new Account("Lyra Margin Accounts", "LyraMarginNFTs");

    aggregator = new MockV3Aggregator(18, 1000e18);
    spotFeeds = new ChainlinkSpotFeeds();
    spotFeeds.addFeed("ETH/USD", address(aggregator), 1 hours);

    auction = new MockDutchAuction();

    option = new Option();
    manager = new PCRM(
      address(account),
      address(spotFeeds),
      address(0), // lending
      address(option),
      address(auction)
    );

    vm.startPrank(alice);
    aliceAcc = account.createAccount(alice, IManager(manager));
    bobAcc = account.createAccount(bob, IManager(manager));
    vm.stopPrank();

    vm.startPrank(bob);
    account.approve(alice, bobAcc);
    vm.stopPrank();
  }

  //////////////
  // Transfer //
  //////////////

  function testHandleAdjustment() public {
    vm.startPrank(alice);
    AccountStructs.AssetTransfer memory assetTransfer = AccountStructs.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAsset(option),
      subId: 1,
      amount: 1e18,
      assetData: ""
    });
    account.submitTransfer(assetTransfer, "");
    vm.stopPrank();

    // todo: actually do manager
  }

  /////////////////////////
  // Margin calculations //
  /////////////////////////

  function testInitialMarginCalculation() public view {
    PCRM.StrikeHolding[] memory strikes = new PCRM.StrikeHolding[](1);
    strikes[0] = PCRM.StrikeHolding({strike: 0, calls: 0, puts: 0, forwards: 0});

    PCRM.ExpiryHolding[] memory expiries = new PCRM.ExpiryHolding[](1);
    expiries[0] = PCRM.ExpiryHolding({expiry: 0, strikes: strikes});

    manager.getInitialMargin(expiries);

    // todo: actually test
  }

  function testMaintenanceMarginCalculation() public view {
    PCRM.StrikeHolding[] memory strikes = new PCRM.StrikeHolding[](1);
    strikes[0] = PCRM.StrikeHolding({strike: 0, calls: 0, puts: 0, forwards: 0});

    PCRM.ExpiryHolding[] memory expiries = new PCRM.ExpiryHolding[](1);
    expiries[0] = PCRM.ExpiryHolding({expiry: 0, strikes: strikes});

    manager.getMaintenanceMargin(expiries);

    // todo: actually test
  }

  ////////////////////
  // Manager Change //
  ////////////////////

  function testValidManagerChange() public {
    MockManager newManager = new MockManager(address(account));

    // todo: test change to valid manager
    vm.startPrank(address(alice));
    account.changeManager(aliceAcc, IManager(address(newManager)), "");
    vm.stopPrank();
  }

  //////////////////
  // Liquidations //
  //////////////////

  function testCheckAndStartLiquidation() public {
    manager.checkAndStartLiquidation(aliceAcc);
  }

  function testExecuteBid() public {
    vm.startPrank(address(auction));
    manager.executeBid(aliceAcc, 0, 5e17, 0);
    vm.stopPrank();
  }

  //////////
  // View //
  //////////

  function testGetSortedHoldings() public {
    vm.startPrank(address(alice));
    manager.getSortedHoldings(aliceAcc);
    vm.stopPrank();
  }
}
