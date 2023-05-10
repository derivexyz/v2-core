pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "src/assets/Option.sol";
import "src/risk-managers/PCRM.sol";
import "src/assets/CashAsset.sol";
import "src/Accounts.sol";
import {IManager} from "src/interfaces/IManager.sol";
import {IAsset} from "src/interfaces/IAsset.sol";

import "test/shared/mocks/MockManager.sol";
import "test/shared/mocks/MockERC20.sol";
import "test/shared/mocks/MockAsset.sol";
import "test/shared/mocks/MockOption.sol";
import "test/shared/mocks/MockSM.sol";
import "test/shared/mocks/MockFeed.sol";
import "test/risk-managers/mocks/MockSpotJumpOracle.sol";

import "test/risk-managers/mocks/MockDutchAuction.sol";

contract UNIT_TestPCRM is Test {
  Accounts account;
  PCRM manager;
  MockAsset cash;
  MockERC20 usdc;

  MockFeed feed;
  MockSpotJumpOracle spotJumpOracle;
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

    feed = new MockFeed();
    feed.setSpot(1000e18);

    usdc = new MockERC20("USDC", "USDC");

    auction = new MockDutchAuction();

    option = new MockOption(account);
    cash = new MockAsset(usdc, account, true);
    spotJumpOracle = new MockSpotJumpOracle();

    manager = new PCRM(
      account,
      feed,
      feed,
      ICashAsset(address(cash)),
      option,
      address(auction),
      ISpotJumpOracle(address(spotJumpOracle))
    );

    // cash.setWhitWelistManager(address(manager), true);
    manager.setParams(
      IPCRM.SpotShockParams({
        upInitial: 120e16,
        downInitial: 80e16,
        upMaintenance: 110e16,
        downMaintenance: 90e16,
        timeSlope: 1e18
      }),
      IPCRM.VolShockParams({
        minVol: 1e18,
        maxVol: 3e18,
        timeA: 30 days,
        timeB: 90 days,
        spotJumpMultipleSlope: 5e18,
        spotJumpMultipleLookback: 1 days
      }),
      IPCRM.PortfolioDiscountParams({
        maintenance: 90e16, // 90%
        initial: 80e16, // 80%
        initialStaticCashOffset: 0,
        riskFreeRate: 10e16 // 10%
      })
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

  //////////////
  // Transfer //
  //////////////

  function testBlockTradeIfMultipleExpiries() public {
    _depositCash(alice, aliceAcc, 5000e18);
    _depositCash(bob, bobAcc, 5000e18);
    // prepare trades
    uint callSubId = OptionEncoding.toSubId(block.timestamp + 1 days, 1000e18, true);
    uint longtermSubId = OptionEncoding.toSubId(block.timestamp + 365 days, 10e18, false);
    IAccounts.AssetTransfer memory callTransfer = IAccounts.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAsset(option),
      subId: callSubId,
      amount: 1e18,
      assetData: ""
    });
    IAccounts.AssetTransfer memory longtermTransfer = IAccounts.AssetTransfer({
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
    IAccounts.AssetTransfer memory assetTransfer = IAccounts.AssetTransfer({
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

  function testCanHandleEmptyAdjustments() public {
    address caller = address(0xca11);
    vm.prank(address(account));
    IAccounts.AssetDelta[] memory emptyDeltas = new IAccounts.AssetDelta[](0);
    manager.handleAdjustment(aliceAcc, 2, caller, emptyDeltas, "");
  }

  /////////////////////////
  // Margin calculations //
  /////////////////////////

  function testEmptyInitialMarginCalculation() public view {
    IBaseManager.Strike[] memory strikes = new IBaseManager.Strike[](1);
    strikes[0] = IBaseManager.Strike({strike: 0, calls: 0, puts: 0, forwards: 0});

    IBaseManager.Portfolio memory portfolio =
      IBaseManager.Portfolio({cash: 0, perp: 0, expiry: 0, numStrikesHeld: 0, strikes: strikes});

    manager.getInitialMargin(portfolio);

    manager.getInitialMarginWithoutJumpMultiple(portfolio);

    // todo: actually test
  }

  function testEmptyMaintenanceMarginCalculation() public view {
    IBaseManager.Strike[] memory strikes = new IBaseManager.Strike[](1);
    strikes[0] = IBaseManager.Strike({strike: 0, calls: 0, puts: 0, forwards: 0});

    IBaseManager.Portfolio memory expiry =
      IBaseManager.Portfolio({cash: 0, perp: 0, expiry: 0, numStrikesHeld: 0, strikes: strikes});

    manager.getMaintenanceMargin(expiry);

    // todo: actually test
  }

  function testInitialMarginCalculation() public view {
    IBaseManager.Strike[] memory strikes = new IBaseManager.Strike[](2);
    strikes[0] = IBaseManager.Strike({strike: 1000e18, calls: 1e18, puts: 0, forwards: 0});
    strikes[1] = IBaseManager.Strike({strike: 0e18, calls: 1e18, puts: 0, forwards: 0});

    IBaseManager.Portfolio memory expiry =
      IBaseManager.Portfolio({cash: 0, perp: 0, expiry: block.timestamp + 1 days, numStrikesHeld: 2, strikes: strikes});

    manager.getInitialMargin(expiry);

    // todo: actually test
  }

  function testNegativePnLSettledExpiryCalculation() public {
    skip(30 days);
    IBaseManager.Strike[] memory strikes = new IBaseManager.Strike[](2);
    strikes[0] = IBaseManager.Strike({strike: 1000e18, calls: 1e18, puts: 0, forwards: 0});
    strikes[1] = IBaseManager.Strike({strike: 0e18, calls: 1e18, puts: 0, forwards: 0});

    feed.setSpot(100e18);
    uint expiryTimestamp = block.timestamp - 1 days;

    feed.setForwardPrice(expiryTimestamp, 100e18);
    IBaseManager.Portfolio memory expiry =
      IBaseManager.Portfolio({cash: 0, perp: 0, expiry: expiryTimestamp, numStrikesHeld: 2, strikes: strikes});

    manager.getInitialMargin(expiry);

    // todo: actually test, added for coverage
  }

  function testPositivePnLSettledExpiryCalculation() public {
    skip(30 days);
    IBaseManager.Strike[] memory strikes = new IBaseManager.Strike[](1);
    strikes[0] = IBaseManager.Strike({strike: 1000e18, calls: 1e18, puts: 0, forwards: 0});

    uint expiryTimestamp = block.timestamp - 1 days;

    feed.setForwardPrice(expiryTimestamp, 2000e18);
    IBaseManager.Portfolio memory expiry =
      IBaseManager.Portfolio({cash: 0, perp: 0, expiry: expiryTimestamp, numStrikesHeld: 1, strikes: strikes});

    manager.getInitialMargin(expiry);

    // todo: actually test, added for coverage
  }

  function testCanBypassCashCheck() public {
    manager.setFeeRecipient(feeRecipient);
    // alice open 1 long call, short 10 put
    _openDefaultOptions();

    // set price to 0. Alice is insolvent
    feed.setSpot(0);

    IBaseManager.Portfolio memory portfolio = manager.getPortfolio(aliceAcc);
    int marginBefore = manager.getInitialMargin(portfolio);

    // margin is negative
    assertLt(marginBefore, 0);

    uint amountCashToAdd = 1000e18;
    _depositCash(alice, aliceAcc, amountCashToAdd);

    IBaseManager.Portfolio memory portfolioAfter = manager.getPortfolio(aliceAcc);
    int marginAfter = manager.getInitialMargin(portfolioAfter);
    assertEq(marginAfter, marginBefore + int(amountCashToAdd));
  }

  ////////////////////
  // Manager Change //
  ////////////////////

  function testValidManagerChange() public {
    MockManager newManager = new MockManager(address(account));

    // first fails the change
    vm.startPrank(alice);
    vm.expectRevert(
      abi.encodeWithSelector(BaseManager.BM_ManagerNotWhitelisted.selector, aliceAcc, address(newManager))
    );
    account.changeManager(aliceAcc, IManager(address(newManager)), "");
    vm.stopPrank();

    // should pass once approved
    manager.setWhitelistManager(address(newManager), true);
    vm.startPrank(alice);
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
    vm.expectRevert(abi.encodeWithSelector(PCRM.PCRM_MarginRequirementNotMet.selector, int(-5362191780821917808000)));
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

    (IBaseManager.Portfolio memory holding) = manager.getPortfolio(aliceAcc);
    assertEq(holding.strikes[0].strike, 1000e18);
    assertEq(holding.strikes[0].calls, 0);
    assertEq(holding.strikes[0].puts, -9e18);
    assertEq(holding.strikes[0].forwards, 1e18);
  }

  function _transferCash() internal {
    vm.startPrank(address(alice));
    IAccounts.AssetTransfer memory cashTransfer = IAccounts.AssetTransfer({
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

    IAccounts.AssetTransfer[] memory transfers = new IAccounts.AssetTransfer[](2);

    transfers[0] = IAccounts.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAsset(option),
      subId: callSubId,
      amount: 1e18,
      assetData: ""
    });
    transfers[1] = IAccounts.AssetTransfer({
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
