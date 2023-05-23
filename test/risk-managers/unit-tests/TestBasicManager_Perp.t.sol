pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "src/risk-managers/BasicManager.sol";
import "src/risk-managers/SettlementHelper.sol";

import "src/Accounts.sol";
import {IManager} from "src/interfaces/IManager.sol";
import {IBaseManager} from "src/interfaces/IBaseManager.sol";
import {IAsset} from "src/interfaces/IAsset.sol";

import "test/shared/mocks/MockManager.sol";
import "test/shared/mocks/MockERC20.sol";
import "test/shared/mocks/MockPerp.sol";
import "test/shared/mocks/MockOption.sol";
import "test/shared/mocks/MockFeeds.sol";
import "test/shared/mocks/MockOptionPricing.sol";

import "test/auction/mocks/MockCashAsset.sol";

contract UNIT_TestBasicManager is Test {
  Accounts account;
  BasicManager manager;
  MockCash cash;
  MockERC20 usdc;
  MockPerp perp;
  MockOption option;
  MockFeeds stableFeed;
  SettlementHelper settlementHelper;

  MockFeeds feed;

  address alice = address(0xaa);
  address bob = address(0xbb);
  uint aliceAcc;
  uint bobAcc;

  function setUp() public {
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    usdc = new MockERC20("USDC", "USDC");

    cash = new MockCash(usdc, account);

    perp = new MockPerp(account);

    option = new MockOption(account);

    feed = new MockFeeds();
    stableFeed = new MockFeeds();

    manager = new BasicManager(
      account,
      ICashAsset(address(cash))
    );

    manager.whitelistAsset(perp, 1, IBasicManager.AssetType.Perpetual);
    manager.whitelistAsset(option, 1, IBasicManager.AssetType.Option);

    manager.setOraclesForMarket(1, feed, feed, feed, feed, feed);

    manager.setStableFeed(stableFeed);
    stableFeed.setSpot(1e18, 1e18);
    manager.setDepegParameters(IBasicManager.DepegParams(0.98e18, 1.3e18));

    aliceAcc = account.createAccountWithApproval(alice, address(this), manager);
    bobAcc = account.createAccountWithApproval(bob, address(this), manager);

    feed.setSpot(1500e18, 1e18);

    usdc.mint(address(this), 10000e18);
    usdc.approve(address(cash), type(uint).max);

    // settler
    settlementHelper = new SettlementHelper();
  }

  /////////////
  // Setters //
  /////////////

  function testSetPricingModule() public {
    MockOptionPricing pricing = new MockOptionPricing();
    manager.setPricingModule(1, pricing);
    assertEq(address(manager.pricingModules(1)), address(pricing));
  }

  ////////////////////
  // Manager Change //
  ////////////////////

  ////////////////////////////
  // Set Margin Requirement //
  ////////////////////////////

  function testCannotSetPerpMarginRequirementFromNonOwner() public {
    vm.startPrank(alice);
    vm.expectRevert();
    manager.setPerpMarginRequirements(1, 0.05e18, 0.1e18);
    vm.stopPrank();
  }

  function setPerpMarginRequirementsRatios() public {
    manager.setPerpMarginRequirements(1, 0.05e18, 0.1e18);
    (uint mmRequirement, uint imRequirement) = manager.perpMarginRequirements(1);

    assertEq(mmRequirement, 0.1e18);
    assertEq(imRequirement, 0.05e18);
  }

  function testCannotSetPerpMMLargerThanIM() public {
    vm.expectRevert(IBasicManager.BM_InvalidMarginRequirement.selector);
    manager.setPerpMarginRequirements(1, 0.1e18, 0.05e18);
  }

  function testCannotSetInvalidPerpMarginRequirement() public {
    vm.expectRevert(IBasicManager.BM_InvalidMarginRequirement.selector);
    manager.setPerpMarginRequirements(1, 0.1e18, 0);

    vm.expectRevert(IBasicManager.BM_InvalidMarginRequirement.selector);
    manager.setPerpMarginRequirements(1, 0.1e18, 1e18);

    vm.expectRevert(IBasicManager.BM_InvalidMarginRequirement.selector);
    manager.setPerpMarginRequirements(1, 1e18, 0.1e18);
    vm.expectRevert(IBasicManager.BM_InvalidMarginRequirement.selector);
    manager.setPerpMarginRequirements(1, 0, 0.1e18);
  }

  ////////////////////
  //  Margin Checks //
  ////////////////////

  function testCannotHaveUnrecognizedAsset() public {
    MockAsset badAsset = new MockAsset(usdc, account, true);
    vm.expectRevert(IBasicManager.BM_UnsupportedAsset.selector);
    IAccounts.AssetTransfer memory transfer = IAccounts.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: badAsset,
      subId: 0,
      amount: 1e18,
      assetData: ""
    });
    account.submitTransfer(transfer, "");
  }

  function testCanTradePerpWithEnoughMargin() public {
    manager.setPerpMarginRequirements(1, 0.05e18, 0.1e18);

    // trade 10 contracts, margin requirement = 10 * 1500 * 0.1 = 1500
    cash.deposit(aliceAcc, 1500e18);
    cash.deposit(bobAcc, 1500e18);

    // trade can go through
    _tradePerpContract(aliceAcc, bobAcc, 10e18);
  }

  function testCannotTradePerpWithInsufficientMargin() public {
    manager.setPerpMarginRequirements(1, 0.05e18, 0.1e18);

    // trade 10 contracts, margin requirement = 10 * 1500 * 0.1 = 1500
    cash.deposit(aliceAcc, 1499e18);
    cash.deposit(bobAcc, 1499e18);

    // trade cannot go through: -1$ under collateralized
    vm.expectRevert(abi.encodeWithSelector(IBasicManager.BM_PortfolioBelowMargin.selector, aliceAcc, 1e18));
    _tradePerpContract(aliceAcc, bobAcc, 10e18);
  }

  function testOracleContingencyOnPerps() public {
    // set oracle contingency params
    manager.setPerpMarginRequirements(1, 0.05e18, 0.1e18);
    manager.setOracleContingencyParams(1, IBasicManager.OracleContingencyParams(0.75e18, 0, 0.1e18));

    // requirement: 10 * 1500 * 0.1 = 1500
    cash.deposit(aliceAcc, 1500e18);
    cash.deposit(bobAcc, 1500e18);
    _tradePerpContract(aliceAcc, bobAcc, 10e18);

    (int imBefore, int mtmBefore) = manager.getMarginAndMarkToMarket(aliceAcc, true, 1);
    (int mmBefore,) = manager.getMarginAndMarkToMarket(aliceAcc, false, 1);
    assertEq(imBefore, 0);

    // update confidence in spot oracle to below threshold
    feed.setSpot(1500e18, 0.7e18);
    (int aliceImAfter, int aliceMtmAfter) = manager.getMarginAndMarkToMarket(aliceAcc, true, 1);
    (int bobIMAfter, int bobMtmAfter) = manager.getMarginAndMarkToMarket(bobAcc, true, 1);
    (int mmAfter,) = manager.getMarginAndMarkToMarket(aliceAcc, false, 1);

    // (1 - 0.7) * (1500) * 10 * 0.1 = -450
    assertEq(bobIMAfter, -450e18);
    assertEq(aliceImAfter, -450e18);

    // mtm is not affected
    assertEq(mtmBefore, aliceMtmAfter);
    assertEq(mtmBefore, bobMtmAfter);

    // maintenance margin is not affected
    assertEq(mmAfter, mmBefore);
  }

  //======================================
  //        Settlement   Tests
  //======================================

  // tests around settling perp's unrealized PNL with spot
  function testCannotSettleWithMaliciousPerpContract() public {
    MockPerp badPerp = new MockPerp(account);
    vm.expectRevert(IBasicManager.BM_UnsupportedAsset.selector);
    manager.settlePerpsWithIndex(badPerp, aliceAcc);
  }

  function testNoCashMovesIfNothingToSettle() public {
    int cashBefore = _getCashBalance(aliceAcc);
    perp.mockAccountPnlAndFunding(aliceAcc, 0, 0);
    manager.settlePerpsWithIndex(perp, aliceAcc);
    int cashAfter = _getCashBalance(aliceAcc);
    assertEq(cashAfter, cashBefore);
  }

  function testCashChangesBasedOnPerpContractPNLAndFundingValues() public {
    int cashBefore = _getCashBalance(aliceAcc);
    perp.mockAccountPnlAndFunding(aliceAcc, 1e18, 100e18);
    manager.settlePerpsWithIndex(perp, aliceAcc);
    int cashAfter = _getCashBalance(aliceAcc);
    assertEq(cashAfter - cashBefore, 101e18);
  }

  function testSettlePerpWithManagerData() public {
    int cashBefore = _getCashBalance(aliceAcc);
    perp.mockAccountPnlAndFunding(aliceAcc, 0, 100e18);

    bytes memory data = abi.encode(address(manager), address(perp), aliceAcc);
    IBaseManager.ManagerData[] memory allData = new IBaseManager.ManagerData[](1);
    allData[0] = IBaseManager.ManagerData({receiver: address(settlementHelper), data: data});
    bytes memory managerData = abi.encode(allData);

    // only transfer 0 cash
    IAccounts.AssetTransfer memory transfer =
      IAccounts.AssetTransfer({fromAcc: aliceAcc, toAcc: bobAcc, asset: cash, subId: 0, amount: 0, assetData: ""});
    account.submitTransfer(transfer, managerData);

    int cashAfter = _getCashBalance(aliceAcc);
    assertEq(cashAfter - cashBefore, 100e18);
  }

  function testCannotSettleWithBadPerp() public {
    MockPerp badPerp = new MockPerp(account);
    badPerp.mockAccountPnlAndFunding(aliceAcc, 0, 100e18);

    bytes memory data = abi.encode(address(manager), address(badPerp), aliceAcc);
    IBaseManager.ManagerData[] memory allData = new IBaseManager.ManagerData[](1);
    allData[0] = IBaseManager.ManagerData({receiver: address(settlementHelper), data: data});
    bytes memory managerData = abi.encode(allData);

    // only transfer 0 cash
    IAccounts.AssetTransfer memory transfer =
      IAccounts.AssetTransfer({fromAcc: aliceAcc, toAcc: bobAcc, asset: cash, subId: 0, amount: 0, assetData: ""});

    vm.expectRevert(IBasicManager.BM_UnsupportedAsset.selector);
    account.submitTransfer(transfer, managerData);
  }

  function testCanSettleIntoNegativeCash() public {
    perp.mockAccountPnlAndFunding(aliceAcc, 0, -10000e18);
    manager.settlePerpsWithIndex(perp, aliceAcc);
    assertLt(_getCashBalance(aliceAcc), 0);
  }

  function testCannotHaveNegativeCash() public {
    // assume alice has 1000 unrealized pnl (report by perp contract)
    perp.mockAccountPnlAndFunding(aliceAcc, 0, 1000e18);
    IAccounts.AssetTransfer memory transfer =
      IAccounts.AssetTransfer({fromAcc: aliceAcc, toAcc: bobAcc, asset: cash, subId: 0, amount: 1000e18, assetData: ""});

    vm.expectRevert(IBasicManager.BM_NoNegativeCash.selector);
    account.submitTransfer(transfer, "");
  }

  function _tradePerpContract(uint fromAcc, uint toAcc, int amount) internal {
    IAccounts.AssetTransfer memory transfer =
      IAccounts.AssetTransfer({fromAcc: fromAcc, toAcc: toAcc, asset: perp, subId: 0, amount: amount, assetData: ""});
    account.submitTransfer(transfer, "");
  }

  function _getCashBalance(uint acc) public view returns (int) {
    return account.getBalance(acc, cash, 0);
  }
}
