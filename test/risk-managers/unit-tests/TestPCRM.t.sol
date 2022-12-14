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

contract UNIT_TestPCRM is Test {
  Account account;
  PCRM manager;

  ChainlinkSpotFeeds spotFeeds; //todo: should replace with generic mock
  MockV3Aggregator aggregator;
  Option option;

  address alice = address(0xaa);
  address bob = address(0xbb);
  uint aliceAcc;
  uint bobAcc;

  function setUp() public {
    account = new Account("Lyra Margin Accounts", "LyraMarginNFTs");

    aggregator = new MockV3Aggregator(18, 1000e18);
    spotFeeds = new ChainlinkSpotFeeds();
    spotFeeds.addFeed("ETH/USD", address(aggregator), 1 hours);

    option = new Option();
    manager = new PCRM(
      address(account),
      address(spotFeeds),
      address(0), // lending
      address(option)
    );

    vm.startPrank(alice);
    aliceAcc = account.createAccount(alice, IManager(manager));
    bobAcc = account.createAccount(bob, IManager(manager));
  }

  //////////////
  // Transfer //
  //////////////

  function testWhitelistManagerCheck() public {
    AccountStructs.AssetTransfer memory assetTransfer = AccountStructs.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAsset(option),
      subId: 1,
      amount: 1e18,
      assetData: ''
    });
    account.submitTransfer(assetTransfer, '');

    // todo: actually do manager
  }

  /////////////////////////
  // Margin calculations //
  /////////////////////////

  function testInitialMarginCalculation() public view {
    PCRM.StrikeHolding[] memory strikes = 
      new PCRM.StrikeHolding[](1);
    strikes[0] = PCRM.StrikeHolding({
      strike: 0,
      calls: 0,
      puts: 0,
      forwards: 0
    });

    PCRM.ExpiryHolding[] memory expiries = 
      new PCRM.ExpiryHolding[](1);
    expiries[0] = PCRM.ExpiryHolding({
      expiry: 0, 
      strikes: strikes
    });

    manager.getInitialMargin(expiries);

    // todo: actually test
  }

  function testMaintenanceMarginCalculation() public view {
    PCRM.StrikeHolding[] memory strikes = 
      new PCRM.StrikeHolding[](1);
    strikes[0] = PCRM.StrikeHolding({
      strike: 0,
      calls: 0,
      puts: 0,
      forwards: 0
    });

    PCRM.ExpiryHolding[] memory expiries = 
      new PCRM.ExpiryHolding[](1);
    expiries[0] = PCRM.ExpiryHolding({
      expiry: 0, 
      strikes: strikes
    });

    manager.getMaintenanceMargin(expiries);

    // todo: actually test
  }

  ////////////////////
  // Manager Change //
  ////////////////////

  function testValidManagerChange() public {
    MockManager newManager = new MockManager(address(account));


    // todo: test change to valid manager
    account.changeManager(aliceAcc, IManager(address(newManager)), '');
  }

}