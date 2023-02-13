pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "test/feeds/mocks/MockV3Aggregator.sol";
import "src/feeds/ChainlinkSpotFeeds.sol";
import "src/assets/Option.sol";
import "src/risk-managers/PCRM.sol";
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

contract UNIT_TestPCRM is Test {
  Accounts account;
  PCRM manager;
  MockAsset cash;
  MockERC20 usdc;

  ChainlinkSpotFeeds spotFeeds; //todo: should replace with generic mock
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

    auction = new MockDutchAuction();

    option = new MockOption(account);
    cash = new MockAsset(usdc, account, true);

    manager = new PCRM(
      account,
      spotFeeds,
      ICashAsset(address(cash)),
      option,
      address(auction)
    );

    // cash.setWhitWelistManager(address(manager), true);
    manager.setParams(
      PCRM.Shocks({
        spotUpInitial: 120e16,
        spotDownInitial: 80e16,
        spotUpMaintenance: 110e16,
        spotDownMaintenance: 90e16,
        vol: 300e16,
        rfr: 10e16
      }),
      PCRM.Discounts({maintenanceStaticDiscount: 90e16, initialStaticDiscount: 80e16})
    );

    feeRecipient = account.createAccount(address(this), manager);

    vm.startPrank(alice);
    aliceAcc = account.createAccount(alice, IManager(manager));
    bobAcc = account.createAccount(bob, IManager(manager));
    vm.stopPrank();

    vm.startPrank(bob);
    account.approve(alice, bobAcc);
    vm.stopPrank();
  }

  ///////////
  // Admin //
  ///////////

  function testSetParamsWithNonOwner() public {
    vm.startPrank(alice);
    vm.expectRevert(AbstractOwned.OnlyOwner.selector);
    manager.setParams(
      PCRM.Shocks({
        spotUpInitial: 120e16,
        spotDownInitial: 80e16,
        spotUpMaintenance: 110e16,
        spotDownMaintenance: 90e16,
        vol: 300e16,
        rfr: 10e16
      }),
      PCRM.Discounts({maintenanceStaticDiscount: 90e16, initialStaticDiscount: 80e16})
    );
    vm.stopPrank();
  }

  function testSetParamsWithOwner() public {
    manager.setParams(
      PCRM.Shocks({
        spotUpInitial: 200e16,
        spotDownInitial: 50e16,
        spotUpMaintenance: 120e16,
        spotDownMaintenance: 70e16,
        vol: 400e16,
        rfr: 20e16
      }),
      PCRM.Discounts({maintenanceStaticDiscount: 85e16, initialStaticDiscount: 75e16})
    );

    (uint spotUpInitial, uint spotDownInitial, uint spotUpMaintenance, uint spotDownMaintenance, uint vol, uint rfr) =
      manager.shocks();
    assertEq(spotUpInitial, 200e16);
    assertEq(spotDownInitial, 50e16);
    assertEq(spotUpMaintenance, 120e16);
    assertEq(spotDownMaintenance, 70e16);
    assertEq(vol, 400e16);
    assertEq(rfr, 20e16);

    (uint maintenanceStaticDiscount, uint initialStaticDiscount) = manager.discounts();
    assertEq(maintenanceStaticDiscount, 85e16);
    assertEq(initialStaticDiscount, 75e16);
  }

  //////////////
  // Transfer //
  //////////////

  function testBlockTradeIfMultipleExpiries() public {
    _depositCash(alice, aliceAcc, 5000e18);
    _depositCash(bob, bobAcc, 5000e18);
    // prepare trades
    uint callSubId = OptionEncoding.toSubId(block.timestamp + 1 days, 1000e18, true);
    uint longtermSubId = OptionEncoding.toSubId(block.timestamp + 365 days, 10e18, false);
    AccountStructs.AssetTransfer memory callTransfer = AccountStructs.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAsset(option),
      subId: callSubId,
      amount: 1e18,
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

    // open first expiry option
    vm.startPrank(address(alice));
    account.submitTransfer(callTransfer, "");

    // fail when adding an option with a new expiry
    vm.expectRevert(BaseManager.BM_OnlySingleExpiryPerAccount.selector);
    account.submitTransfer(longtermTransfer, "");
    vm.stopPrank();
  }

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

  function testEmptyInitialMarginCalculation() public view {
    BaseManager.Strike[] memory strikes = new BaseManager.Strike[](1);
    strikes[0] = BaseManager.Strike({strike: 0, calls: 0, puts: 0, forwards: 0});

    BaseManager.Portfolio memory expiry =
      BaseManager.Portfolio({cash: 0, expiry: 0, numStrikesHeld: 0, strikes: strikes});

    manager.getInitialMargin(expiry);

    // todo: actually test
  }

  function testEmptyMaintenanceMarginCalculation() public view {
    BaseManager.Strike[] memory strikes = new BaseManager.Strike[](1);
    strikes[0] = BaseManager.Strike({strike: 0, calls: 0, puts: 0, forwards: 0});

    BaseManager.Portfolio memory expiry =
      BaseManager.Portfolio({cash: 0, expiry: 0, numStrikesHeld: 0, strikes: strikes});

    manager.getMaintenanceMargin(expiry);

    // todo: actually test
  }

  function testInitialMarginCalculation() public view {
    BaseManager.Strike[] memory strikes = new BaseManager.Strike[](2);
    strikes[0] = BaseManager.Strike({strike: 1000e18, calls: 1e18, puts: 0, forwards: 0});
    strikes[1] = BaseManager.Strike({strike: 0e18, calls: 1e18, puts: 0, forwards: 0});

    BaseManager.Portfolio memory expiry =
      BaseManager.Portfolio({cash: 0, expiry: block.timestamp + 1 days, numStrikesHeld: 2, strikes: strikes});

    manager.getInitialMargin(expiry);

    // todo: actually test
  }

  function testNegativePnLSettledExpiryCalculation() public {
    skip(30 days);
    BaseManager.Strike[] memory strikes = new BaseManager.Strike[](2);
    strikes[0] = BaseManager.Strike({strike: 1000e18, calls: 1e18, puts: 0, forwards: 0});
    strikes[1] = BaseManager.Strike({strike: 0e18, calls: 1e18, puts: 0, forwards: 0});

    aggregator.updateRoundData(2, 100e18, block.timestamp, block.timestamp, 2);
    BaseManager.Portfolio memory expiry =
      BaseManager.Portfolio({cash: 0, expiry: block.timestamp - 1 days, numStrikesHeld: 2, strikes: strikes});

    manager.getInitialMargin(expiry);

    // todo: actually test, added for coverage
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
    manager.setFeeRecipient(feeRecipient);
    // add some usdc for buffer
    usdc.mint(bob, 1000_000e18);
    vm.startPrank(bob);
    usdc.approve(address(cash), type(uint).max);
    cash.deposit(bobAcc, 0, 1000_000e18);
    vm.stopPrank();

    // alice open 1 long call, short 10 put
    (uint callId, uint putId) = _openDefaultOptions();

    // alice transfer cash to bob
    _transferCash();

    // alice has 3 positions
    int aliceCashBefore = account.getBalance(aliceAcc, cash, 0);
    int bobCashBefore = account.getBalance(bobAcc, cash, 0);
    assertEq(account.getAccountBalances(aliceAcc).length, 3);

    uint exerciseCashAmount = 50e18;
    uint fee = 5e18;
    // 20% got liquidated

    vm.prank(address(auction));
    manager.executeBid(aliceAcc, bobAcc, 0.2e18, exerciseCashAmount, fee);

    assertEq(account.getAccountBalances(aliceAcc).length, 3);
    assertEq(account.getBalance(aliceAcc, option, callId), 0.8e18); // 80% of +1 long call
    assertEq(account.getBalance(aliceAcc, option, putId), -8e18); // 80% of -10 short put

    // alice got 80% of her cash left + amount paid
    int aliceCashAfter = account.getBalance(aliceAcc, cash, 0);
    assertEq(aliceCashBefore * 4 / 5 + int(exerciseCashAmount), aliceCashAfter);

    // bob's is increased by 20% of alice cash - amount paid to alice - fee
    int bobCashAfter = account.getBalance(bobAcc, cash, 0);
    assertEq(aliceCashBefore * 1 / 5 - int(exerciseCashAmount) - int(fee), bobCashAfter - bobCashBefore);

    assertEq(account.getBalance(feeRecipient, cash, 0), int(fee));
  }

  function testCannotExecuteBidIfLiquidatorBecomesUnderwater() public {
    manager.setFeeRecipient(feeRecipient);
    // alice open 1 long call, short 10 put
    _openDefaultOptions();

    uint exerciseCashAmount = 10000e18; // paying gigantic amount that makes liquidator insolvent
    vm.expectRevert(abi.encodeWithSelector(PCRM.PCRM_MarginRequirementNotMet.selector, int(-5360e18)));
    vm.prank(address(auction));
    manager.executeBid(aliceAcc, bobAcc, 0.2e18, exerciseCashAmount, 0);
  }

  function testExecuteEmptyBidOnEmptyAccount() public {
    manager.setFeeRecipient(feeRecipient);
    assertEq(account.getAccountBalances(aliceAcc).length, 0);

    vm.prank(address(auction));
    manager.executeBid(aliceAcc, bobAcc, 0.5e18, 0, 0);

    assertEq(account.getAccountBalances(aliceAcc).length, 0);
  }

  function testCannotExecuteBidWithPortionGreaterThan100() public {
    vm.expectRevert(PCRM.PCRM_InvalidBidPortion.selector);
    vm.prank(address(auction));
    manager.executeBid(aliceAcc, bobAcc, 1e18 + 1, 0, 0);
  }

  //////////
  // View //
  //////////

  function testGetPortfolio() public {
    _openDefaultOptions();

    _transferCash();

    (BaseManager.Portfolio memory holding) = manager.getPortfolio(aliceAcc);
    assertEq(holding.strikes[0].strike, 1000e18);
    assertEq(holding.strikes[0].calls, 0);
    assertEq(holding.strikes[0].puts, -9e18);
    assertEq(holding.strikes[0].forwards, 1e18);
  }

  function _transferCash() internal {
    vm.startPrank(address(alice));
    AccountStructs.AssetTransfer memory cashTransfer = AccountStructs.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: IAsset(address(cash)),
      subId: 0,
      amount: 1000e18,
      assetData: ""
    });
    account.submitTransfer(cashTransfer, "");
    vm.stopPrank();
  }

  // alice open 1 long call, 10 short put. both with 4K cash
  function _openDefaultOptions() internal returns (uint callSubId, uint putSubId) {
    _depositCash(alice, aliceAcc, 4000e18);
    _depositCash(bob, bobAcc, 4000e18);

    vm.startPrank(address(alice));
    callSubId = OptionEncoding.toSubId(block.timestamp + 1 days, 1000e18, true);
    putSubId = OptionEncoding.toSubId(block.timestamp + 1 days, 1000e18, false);

    AccountStructs.AssetTransfer[] memory transfers = new AccountStructs.AssetTransfer[](2);

    transfers[0] = AccountStructs.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAsset(option),
      subId: callSubId,
      amount: 1e18,
      assetData: ""
    });
    transfers[1] = AccountStructs.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAsset(option),
      subId: putSubId,
      amount: -10e18,
      assetData: ""
    });
    account.submitTransfers(transfers, "");
    vm.stopPrank();
  }

  function _depositCash(address user, uint acc, uint amount) internal {
    usdc.mint(user, amount);
    vm.startPrank(user);
    usdc.approve(address(cash), type(uint).max);
    cash.deposit(acc, 0, amount);
    vm.stopPrank();
  }
}
