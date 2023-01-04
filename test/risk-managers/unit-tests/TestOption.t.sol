pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "test/feeds/mocks/MockV3Aggregator.sol";
import "src/feeds/ChainlinkSpotFeeds.sol";
import "src/assets/Option.sol";
import "src/Account.sol";
import "src/interfaces/IManager.sol";
import "src/interfaces/IAsset.sol";
import "src/interfaces/AccountStructs.sol";
import "test/shared/mocks/MockManager.sol";

contract UNIT_TestOption is Test {
  Account account;
  MockManager manager;

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
    manager = new MockManager(address(account));

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

  function testWhitelistedManagerCheck() public {
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
  }

  function testValidSubIdCheck() public {
    // todo: test out of bounds subId
  }

  ////////////////////
  // Manager Change //
  ////////////////////

  function testValidManagerChange() public {
    /* ensure account holds asset before manager changed*/
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
    MockManager newManager = new MockManager(address(account));

    // todo: test change to valid manager
    account.changeManager(aliceAcc, IManager(address(newManager)), "");
    vm.stopPrank();
  }

  ////////////////
  // Settlement //
  ////////////////

  function testSetSettlementPrice() public {
    // todo: do actual price check
    option.setSettlementPrice(0);
  }

  function testCalcSettlementValue() public view {
    // todo: do actual calc
    option.calcSettlementValue(0, 0);
  }

  ///////////
  // Utils //
  ///////////

  function testDecodeSubId() public view {
    // todo: do actual decode
    option.getOptionDetails(0);
  }

  function testEncodeSubId() public view {
    // todo: do actual encode
    option.getSubId(0, 0, true);
  }
}
