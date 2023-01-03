pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "test/feeds/mocks/MockV3Aggregator.sol";
import "src/feeds/ChainlinkSpotFeeds.sol";
import "src/assets/Option.sol";
import "src/risk-managers/PCRM.sol";
import "src/Accounts.sol";
import "src/interfaces/IManager.sol";
import "src/interfaces/IAsset.sol";
import "src/interfaces/AccountStructs.sol";
import "test/shared/mocks/MockManager.sol";
import "test/risk-managers/mocks/MockDutchAuction.sol";

contract UNIT_TestPCRM is Test {
  Accounts account;
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
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

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
    expiries[0] = PCRM.ExpiryHolding({expiry: 0, numStrikesHeld: 0, strikes: strikes});

    manager.getInitialMargin(expiries, 0);

    // todo: actually test
  }

  function testMaintenanceMarginCalculation() public view {
    PCRM.StrikeHolding[] memory strikes = new PCRM.StrikeHolding[](1);
    strikes[0] = PCRM.StrikeHolding({strike: 0, calls: 0, puts: 0, forwards: 0});

    PCRM.ExpiryHolding[] memory expiries = new PCRM.ExpiryHolding[](1);
    expiries[0] = PCRM.ExpiryHolding({expiry: 0, numStrikesHeld: 0, strikes: strikes});

    manager.getMaintenanceMargin(expiries, 0);

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

  function testGetGroupedHoldings() public {
    _openDefaultOptions();

    (PCRM.ExpiryHolding[] memory holdings) = manager.getGroupedOptions(aliceAcc);
    assertEq(holdings[0].strikes[0].strike, 1000e18);
    assertEq(holdings[0].strikes[0].calls, 0);
    assertEq(holdings[0].strikes[0].puts, -9e18);
    assertEq(holdings[0].strikes[0].forwards, 1e18);

    assertEq(holdings[1].strikes[0].strike, 10e18);
    assertEq(holdings[1].strikes[0].puts, 5e18);
  }

  function _openDefaultOptions() internal {
    vm.startPrank(address(alice));
    uint callSubId = OptionEncoding.toSubId(block.timestamp + 1 days, 1000e18, true);

    uint putSubId = OptionEncoding.toSubId(block.timestamp + 1 days, 1000e18, false);

    uint longtermSubId = OptionEncoding.toSubId(block.timestamp + 365 days, 10e18, false);

    AccountStructs.AssetTransfer memory callTransfer = AccountStructs.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAsset(option),
      subId: callSubId,
      amount: 1e18,
      assetData: ""
    });
    AccountStructs.AssetTransfer memory putTransfer = AccountStructs.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAsset(option),
      subId: putSubId,
      amount: -10e18,
      assetData: ""
    });
    AccountStructs.AssetTransfer memory longtermTransfer = AccountStructs.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAsset(option),
      subId: longtermSubId,
      amount: 5e18,
      assetData: ""
    });
    account.submitTransfer(callTransfer, "");
    account.submitTransfer(putTransfer, "");
    account.submitTransfer(longtermTransfer, "");

    vm.stopPrank();
  }
}
