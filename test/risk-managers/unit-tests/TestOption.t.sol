pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "test/feeds/mocks/MockV3Aggregator.sol";
import "src/feeds/ChainlinkSpotFeeds.sol";
import "src/assets/Option.sol";
import "src/Account.sol";
import "src/interfaces/IManager.sol";
import "test/shared/mocks/MockManager.sol";

contract TestOption is Test {
  Account account;
  MockManager manager;

  ChainlinkSpotFeeds spotFeeds; //todo: should replace with generic mock
  MockV3Aggregator aggregator;
  Option option;

  address alice = address(0xaa);
  uint aliceAcc;

  function setUp() public {
    account = new Account("Lyra Margin Accounts", "LyraMarginNFTs");

    aggregator = new MockV3Aggregator(18, 1000e18);
    spotFeeds = new ChainlinkSpotFeeds();
    spotFeeds.addFeed("ETH/USD", address(aggregator));

    option = new Option();
    manager = new MockManager(address(account));

    vm.startPrank(alice);
    aliceAcc = account.createAccount(alice, IManager(manager));
  }

  //////////////
  // Transfer //
  //////////////

  function testWhitelistedManagerCheck() public {

  }

  function testValidSubIdCheck() public {

  }

  ////////////////////
  // Manager Change //
  ////////////////////


  ////////////////
  // Settlement //
  ////////////////



  ///////////
  // Utils //
  ///////////

}