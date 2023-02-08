pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "test/feeds/mocks/MockV3Aggregator.sol";
import "src/feeds/ChainlinkSpotFeeds.sol";
import "src/assets/Option.sol";
import "src/risk-managers/MLRM.sol";
import "src/assets/CashAsset.sol";
import "src/Accounts.sol";
import "src/interfaces/IManager.sol";
import "src/interfaces/IAsset.sol";
import "src/interfaces/AccountStructs.sol";

import "test/shared/mocks/MockManager.sol";
import "test/shared/mocks/MockERC20.sol";
import "test/shared/mocks/MockAsset.sol";
import "test/shared/mocks/MockOption.sol";
import "test/shared/mocks/MockSM.sol";

import "test/risk-managers/mocks/MockDutchAuction.sol";

contract UNIT_TestMLRM is Test {
  Accounts account;
  MLRM manager;
  MockAsset cash;
  MockERC20 usdc;

  ChainlinkSpotFeeds spotFeeds;
  MockV3Aggregator aggregator;
  MockOption option;
  MockDutchAuction auction;
  MockSM sm;
  uint feeRecipient;

  address alice = address(0xaa);
  address bob = address(0xbb);
  uint aliceAcc;
  uint bobAcc;

  function setUp() public {
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    aggregator = new MockV3Aggregator(18, 1000e18);
    spotFeeds = new ChainlinkSpotFeeds();
    spotFeeds.addFeed("ETH/USD", address(aggregator), 1 hours);
    usdc = new MockERC20("USDC", "USDC");
    option = new MockOption(account);
    cash = new MockAsset(usdc, account, true);

    manager = new MLRM(
      account,
      spotFeeds,
      ICashAsset(address(cash)),
      option
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

  // function testHandleAdjustment() public {
  //   vm.startPrank(alice);
  //   AccountStructs.AssetTransfer memory assetTransfer = AccountStructs.AssetTransfer({
  //     fromAcc: bobAcc,
  //     toAcc: aliceAcc,
  //     asset: IAsset(option),
  //     subId: 1,
  //     amount: 1e18,
  //     assetData: ""
  //   });
  //   account.submitTransfer(assetTransfer, "");
  //   vm.stopPrank();

  //   // todo: actually do manager
  // }

  // /////////////////////////
  // // Margin calculations //
  // /////////////////////////

  // function testEmptyInitialMarginCalculation() public view {
  //   BaseManager.Strike[] memory strikes = new BaseManager.Strike[](1);
  //   strikes[0] = BaseManager.Strike({strike: 0, calls: 0, puts: 0, forwards: 0});

  //   BaseManager.Portfolio memory expiry =
  //     BaseManager.Portfolio({cash: 0, expiry: 0, numStrikesHeld: 0, strikes: strikes});

  //   manager.getInitialMargin(expiry);

  //   // todo: actually test
  // }

  // function testEmptyMaintenanceMarginCalculation() public view {
  //   BaseManager.Strike[] memory strikes = new BaseManager.Strike[](1);
  //   strikes[0] = BaseManager.Strike({strike: 0, calls: 0, puts: 0, forwards: 0});

  //   BaseManager.Portfolio memory expiry =
  //     BaseManager.Portfolio({cash: 0, expiry: 0, numStrikesHeld: 0, strikes: strikes});

  //   manager.getMaintenanceMargin(expiry);

  //   // todo: actually test
  // }

  // function testInitialMarginCalculation() public view {
  //   BaseManager.Strike[] memory strikes = new BaseManager.Strike[](2);
  //   strikes[0] = BaseManager.Strike({strike: 1000e18, calls: 1e18, puts: 0, forwards: 0});
  //   strikes[1] = BaseManager.Strike({strike: 0e18, calls: 1e18, puts: 0, forwards: 0});

  //   BaseManager.Portfolio memory expiry =
  //     BaseManager.Portfolio({cash: 0, expiry: block.timestamp + 1 days, numStrikesHeld: 2, strikes: strikes});

  //   manager.getInitialMargin(expiry);

  //   // todo: actually test
  // }

  // function testNegativePnLSettledExpiryCalculation() public {
  //   skip(30 days);
  //   BaseManager.Strike[] memory strikes = new BaseManager.Strike[](2);
  //   strikes[0] = BaseManager.Strike({strike: 1000e18, calls: 1e18, puts: 0, forwards: 0});
  //   strikes[1] = BaseManager.Strike({strike: 0e18, calls: 1e18, puts: 0, forwards: 0});

  //   aggregator.updateRoundData(2, 100e18, block.timestamp, block.timestamp, 2);
  //   BaseManager.Portfolio memory expiry =
  //     BaseManager.Portfolio({cash: 0, expiry: block.timestamp - 1 days, numStrikesHeld: 2, strikes: strikes});

  //   manager.getInitialMargin(expiry);

  //   // todo: actually test, added for coverage
  // }

  // ////////////////////
  // // Manager Change //
  // ////////////////////

  // function testValidManagerChange() public {
  //   MockManager newManager = new MockManager(address(account));

  //   // todo: test change to valid manager
  //   vm.startPrank(address(alice));
  //   account.changeManager(aliceAcc, IManager(address(newManager)), "");
  //   vm.stopPrank();
  // }

  // // alice open 1 long call, 10 short put. both with 4K cash
  // function _openDefaultOptions() internal returns (uint callSubId, uint putSubId) {
  //   _depositCash(alice, aliceAcc, 4000e18);
  //   _depositCash(bob, bobAcc, 4000e18);

  //   vm.startPrank(address(alice));
  //   callSubId = OptionEncoding.toSubId(block.timestamp + 1 days, 1000e18, true);
  //   putSubId = OptionEncoding.toSubId(block.timestamp + 1 days, 1000e18, false);

  //   AccountStructs.AssetTransfer[] memory transfers = new AccountStructs.AssetTransfer[](2);

  //   transfers[0] = AccountStructs.AssetTransfer({
  //     fromAcc: bobAcc,
  //     toAcc: aliceAcc,
  //     asset: IAsset(option),
  //     subId: callSubId,
  //     amount: 1e18,
  //     assetData: ""
  //   });
  //   transfers[1] = AccountStructs.AssetTransfer({
  //     fromAcc: bobAcc,
  //     toAcc: aliceAcc,
  //     asset: IAsset(option),
  //     subId: putSubId,
  //     amount: -10e18,
  //     assetData: ""
  //   });
  //   account.submitTransfers(transfers, "");
  //   vm.stopPrank();
  // }

  // function _depositCash(address user, uint acc, uint amount) internal {
  //   usdc.mint(user, amount);
  //   vm.startPrank(user);
  //   usdc.approve(address(cash), type(uint).max);
  //   cash.deposit(acc, 0, amount);
  //   vm.stopPrank();
  // }
}
