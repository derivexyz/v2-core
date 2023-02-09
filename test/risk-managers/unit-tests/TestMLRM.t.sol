pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "test/feeds/mocks/MockV3Aggregator.sol";
import "src/feeds/ChainlinkSpotFeeds.sol";
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
import "test/shared/mocks/MockIPCRM.sol";

import "test/risk-managers/mocks/MockDutchAuction.sol";

contract UNIT_TestMLRM is Test {
  Accounts account;
  MLRM mlrm;
  MockIPCRM pcrm;
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

    mlrm = new MLRM(
      account,
      spotFeeds,
      ICashAsset(address(cash)),
      option
    );

    pcrm = new MockIPCRM(address(account));

    vm.startPrank(alice);
    aliceAcc = account.createAccount(alice, IManager(mlrm));
    bobAcc = account.createAccount(bob, IManager(pcrm));
    vm.stopPrank();

    vm.startPrank(bob);
    account.approve(alice, bobAcc);
    vm.stopPrank();
  }

  ///////////////////////
  // Arrange Portfolio //
  ///////////////////////

  function testBlockIfNegativeCashBalance() public {
    _depositCash(alice, aliceAcc, 2000e18);
    _depositCash(bob, bobAcc, 1000e18);

    // prepare trades
    aggregator.updateRoundData(2, 1000e18, block.timestamp, block.timestamp, 2);
    uint callSubId = OptionEncoding.toSubId(block.timestamp + 1 days, 1000e18, true);
    AccountStructs.AssetTransfer memory callTransfer = AccountStructs.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAsset(option),
      subId: callSubId,
      amount: 1e18,
      assetData: ""
    });
    AccountStructs.AssetTransfer memory cashBorrow = AccountStructs.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: IAsset(cash),
      subId: 0,
      amount: 5000e18,
      assetData: ""
    });
    AccountStructs.AssetTransfer[] memory transferBatch = new AccountStructs.AssetTransfer[](2);
    transferBatch[0] = callTransfer;
    transferBatch[1] = cashBorrow;

    // fail when adding an option with a new expiry
    vm.startPrank(alice);
    vm.expectRevert(MLRM.MLRM_OnlyPositiveCash.selector);
    account.submitTransfers(transferBatch, "");
    vm.stopPrank();
  }

  function testBlockIfUnsupportedOption() public {
    // create unsupported option
    MockOption unsupportedOption = new MockOption(account);

    // prepare trades
    uint callSubId = OptionEncoding.toSubId(block.timestamp + 1 days, 1000e18, true);
    AccountStructs.AssetTransfer memory invalidOption = AccountStructs.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAsset(unsupportedOption),
      subId: callSubId,
      amount: 1e18,
      assetData: ""
    });
    AccountStructs.AssetTransfer memory validOption = AccountStructs.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: IAsset(option),
      subId: callSubId,
      amount: 5e18,
      assetData: ""
    });
    AccountStructs.AssetTransfer[] memory transferBatch = new AccountStructs.AssetTransfer[](2);
    transferBatch[0] = validOption;
    transferBatch[1] = invalidOption;

    // // fail due to unsupported asset
    vm.startPrank(alice);
    vm.expectRevert(abi.encodeWithSelector(MLRM.MLRM_UnsupportedAsset.selector, address(unsupportedOption)));
    account.submitTransfers(transferBatch, "");
    vm.stopPrank();
  }

  /////////////////////////
  // Margin calculations //
  /////////////////////////

  function testBlockIfUnbounded() public {
    // prepare trades
    uint callSubId = OptionEncoding.toSubId(block.timestamp + 1 days, 1000e18, true);
    AccountStructs.AssetTransfer memory validOption = AccountStructs.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: IAsset(option),
      subId: callSubId,
      amount: 5e18,
      assetData: ""
    });

    // fail as there are <0 calls
    vm.startPrank(alice);
    vm.expectRevert(abi.encodeWithSelector(MLRM.MLRM_PayoffUnbounded.selector, int(-5e18)));
    account.submitTransfer(validOption, "");
    vm.stopPrank();
  }

  function testBlockIfBelowMargin() public {
    // todo [mech, Josh to organize PR]:
    // create separate test file where all cases of valid margin calcs can be tested

    _depositCash(alice, aliceAcc, 100e18);
    _depositCash(bob, bobAcc, 100e18);

    uint putSubId = OptionEncoding.toSubId(block.timestamp + 1 days, 500e18, false);
    AccountStructs.AssetTransfer memory putTransfer = AccountStructs.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: IAsset(option),
      subId: putSubId,
      amount: 1e18,
      assetData: ""
    });
    AccountStructs.AssetTransfer memory premiumTransfer = AccountStructs.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAsset(cash),
      subId: 0,
      amount: 100e18,
      assetData: ""
    });
    AccountStructs.AssetTransfer[] memory transferBatch = new AccountStructs.AssetTransfer[](2);
    transferBatch[0] = putTransfer;
    transferBatch[1] = premiumTransfer;

    // fail as alice will be below margin
    vm.startPrank(alice);
    vm.expectRevert(abi.encodeWithSelector(MLRM.MLRM_PortfolioBelowMargin.selector, uint(aliceAcc), -300e18));
    account.submitTransfers(transferBatch, "");
    vm.stopPrank();
  }

  function testDoubleShortPutMargin() public {
    uint put1SubId = OptionEncoding.toSubId(block.timestamp + 1 days, 1000e18, false);
    uint put2SubId = OptionEncoding.toSubId(block.timestamp + 1 days, 2000e18, false);
    AccountStructs.AssetTransfer memory putTransfer1 = AccountStructs.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: IAsset(option),
      subId: put1SubId,
      amount: 1e18,
      assetData: ""
    });
    AccountStructs.AssetTransfer memory putTransfer2 = AccountStructs.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: IAsset(option),
      subId: put2SubId,
      amount: 1e18,
      assetData: ""
    });
    AccountStructs.AssetTransfer[] memory transferBatch = new AccountStructs.AssetTransfer[](2);
    transferBatch[0] = putTransfer1;
    transferBatch[1] = putTransfer2;

    // fail as alice will be below margin
    vm.startPrank(alice);
    vm.expectRevert(abi.encodeWithSelector(MLRM.MLRM_PortfolioBelowMargin.selector, uint(aliceAcc), -3000e18));
    account.submitTransfers(transferBatch, "");
    vm.stopPrank();
  }

  function testExpiredOption() public {
    // todo: do full test once settlement feed integrated

    // todo [mech, Josh to organize PR]:
    // create separate test file where all cases of valid margin calcs can be tested

    _depositCash(alice, aliceAcc, 100e18);
    _depositCash(bob, bobAcc, 100e18);

    aggregator.updateRoundData(2, 1000e18, block.timestamp, block.timestamp, 2);
    uint callSubId = OptionEncoding.toSubId(block.timestamp + 1 days, 750e18, false);
    AccountStructs.AssetTransfer memory callTransfer = AccountStructs.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAsset(option),
      subId: callSubId,
      amount: 1e18,
      assetData: ""
    });
    vm.startPrank(alice);
    account.submitTransfer(callTransfer, "");
    vm.stopPrank();

    // uses settled price
    skip(3 days);
    aggregator.updateRoundData(3, 800e18, block.timestamp, block.timestamp, 3);
    AccountStructs.AssetTransfer memory premiumTransfer = AccountStructs.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAsset(cash),
      subId: 0,
      amount: 100e18,
      assetData: ""
    });
    vm.startPrank(alice);
    account.submitTransfer(premiumTransfer, "");
    vm.stopPrank();
  }

  function testZeroStrikeOption() public {
    _depositCash(alice, aliceAcc, 100e18);
    _depositCash(bob, bobAcc, 100e18);

    // add ZSC
    aggregator.updateRoundData(2, 1000e18, block.timestamp, block.timestamp, 2);
    uint expiry = block.timestamp + 1 days;
    uint callSubId = OptionEncoding.toSubId(expiry, 0, true);
    AccountStructs.AssetTransfer memory callTransfer = AccountStructs.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAsset(option),
      subId: callSubId,
      amount: 1e18,
      assetData: ""
    });
    vm.startPrank(alice);
    account.submitTransfer(callTransfer, "");
    vm.stopPrank();

    // ZSC valued at $0
    BaseManager.Portfolio memory portfolio = mlrm.getPortfolio(aliceAcc);
    assertEq(mlrm.getMargin(portfolio), 100e18);

    // add short put
    uint putSubId = OptionEncoding.toSubId(expiry, 100e18, false);
    AccountStructs.AssetTransfer memory putTransfer = AccountStructs.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: IAsset(option),
      subId: putSubId,
      amount: 1e18,
      assetData: ""
    });
    vm.startPrank(alice);
    account.submitTransfer(putTransfer, "");
    vm.stopPrank();

    // ZSC and put offset
    portfolio = mlrm.getPortfolio(aliceAcc);
    assertEq(mlrm.getMargin(portfolio), 0);
  }

  // ////////////////////
  // // Manager Change //
  // ////////////////////

  function testValidManagerChange() public {
    MockManager newManager = new MockManager(address(account));

    // todo: test nextManager whitelist once implemented.
    vm.startPrank(alice);
    account.changeManager(aliceAcc, IManager(address(newManager)), "");
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
