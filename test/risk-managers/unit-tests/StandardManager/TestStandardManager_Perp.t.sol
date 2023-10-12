// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../../../src/risk-managers/StandardManager.sol";
import "../../../../src/risk-managers/SRMPortfolioViewer.sol";
import "../../../../src/periphery/PerpSettlementHelper.sol";

import "../../../../src/SubAccounts.sol";
import {IBaseManager} from "../../../../src/interfaces/IBaseManager.sol";
import {IDutchAuction} from "../../../../src/interfaces/IDutchAuction.sol";
import "../../../shared/mocks/MockERC20.sol";
import "../../../shared/mocks/MockPerp.sol";
import "../../../shared/mocks/MockOptionAsset.sol";
import "../../../shared/mocks/MockFeeds.sol";
import "../../../shared/mocks/MockOptionPricing.sol";

import "../../../shared/mocks/MockCash.sol";

contract UNIT_TestStandardManager is Test {
  SubAccounts subAccounts;
  StandardManager manager;
  MockCash cash;
  MockERC20 usdc;
  MockPerp perp;
  MockOption option;
  MockFeeds stableFeed;
  PerpSettlementHelper perpHelper;

  MockFeeds feed;
  SRMPortfolioViewer viewer;

  address alice = address(0xaa);
  address bob = address(0xbb);
  uint aliceAcc;
  uint bobAcc;

  uint marketId;

  function setUp() public {
    subAccounts = new SubAccounts("Lyra Margin Accounts", "LyraMarginNFTs");

    usdc = new MockERC20("USDC", "USDC");

    cash = new MockCash(usdc, subAccounts);

    perp = new MockPerp(subAccounts);

    option = new MockOption(subAccounts);

    feed = new MockFeeds();
    stableFeed = new MockFeeds();
    viewer = new SRMPortfolioViewer(subAccounts, cash);

    manager = new StandardManager(
      subAccounts,
      ICashAsset(address(cash)),
      IDutchAuction(address(0)),
      viewer
    );

    marketId = manager.createMarket("eth");

    viewer.setStandardManager(manager);

    manager.whitelistAsset(perp, marketId, IStandardManager.AssetType.Perpetual);
    manager.whitelistAsset(option, marketId, IStandardManager.AssetType.Option);

    manager.setOraclesForMarket(marketId, feed, feed, feed);

    manager.setStableFeed(stableFeed);
    stableFeed.setSpot(1e18, 1e18);
    manager.setDepegParameters(IStandardManager.DepegParams(0.98e18, 1.3e18));

    aliceAcc = subAccounts.createAccountWithApproval(alice, address(this), manager);
    bobAcc = subAccounts.createAccountWithApproval(bob, address(this), manager);

    feed.setSpot(1500e18, 1e18);
    perp.setMockPerpPrice(1500e18, 1e18);

    usdc.mint(address(this), 10000e18);
    usdc.approve(address(cash), type(uint).max);

    // settler
    perpHelper = new PerpSettlementHelper();

    manager.setWhitelistedCallee(address(perpHelper), true);
  }

  /////////////
  // Setters //
  /////////////

  function testSetPricingModule() public {
    MockOptionPricing pricing = new MockOptionPricing();
    manager.setPricingModule(marketId, pricing);
    // assertEq(address(manager.pricingModules(1)), address(pricing));
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
    manager.setPerpMarginRequirements(marketId, 0.05e18, 0.1e18);
    vm.stopPrank();
  }

  function setPerpMarginRequirementsRatios() public {
    manager.setPerpMarginRequirements(marketId, 0.05e18, 0.1e18);
    (uint mmPerpReq, uint imPerpReq) = manager.perpMarginRequirements(1);

    assertEq(mmPerpReq, 0.1e18);
    assertEq(imPerpReq, 0.05e18);
  }

  function testCannotSetPerpMMLargerThanIM() public {
    vm.expectRevert(IStandardManager.SRM_InvalidPerpMarginParams.selector);
    manager.setPerpMarginRequirements(marketId, 0.1e18, 0.05e18);
  }

  function testCannotSetInvalidPerpMarginRequirement() public {
    vm.expectRevert(IStandardManager.SRM_InvalidPerpMarginParams.selector);
    manager.setPerpMarginRequirements(marketId, 0.1e18, 0);

    vm.expectRevert(IStandardManager.SRM_InvalidPerpMarginParams.selector);
    manager.setPerpMarginRequirements(marketId, 0.1e18, 1e18);

    vm.expectRevert(IStandardManager.SRM_InvalidPerpMarginParams.selector);
    manager.setPerpMarginRequirements(marketId, 1e18, 0.1e18);
    vm.expectRevert(IStandardManager.SRM_InvalidPerpMarginParams.selector);
    manager.setPerpMarginRequirements(marketId, 0, 0.1e18);
  }

  ////////////////////
  //  Margin Checks //
  ////////////////////

  function testCannotHaveUnrecognizedAsset() public {
    MockOption badAsset = new MockOption(subAccounts);
    vm.expectRevert(IStandardManager.SRM_UnsupportedAsset.selector);
    ISubAccounts.AssetTransfer memory transfer = ISubAccounts.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: badAsset,
      subId: 0,
      amount: 1e18,
      assetData: ""
    });
    subAccounts.submitTransfer(transfer, "");
  }

  function testCanTradePerpWithEnoughMargin() public {
    manager.setPerpMarginRequirements(marketId, 0.05e18, 0.1e18);

    // trade 10 contracts, margin requirement = 10 * 1500 * 0.1 = 1500
    cash.deposit(aliceAcc, 1500e18);
    cash.deposit(bobAcc, 1500e18);

    // trade can go through
    _tradePerpContract(aliceAcc, bobAcc, 10e18);
  }

  function testCannotTradePerpWithInsufficientMargin() public {
    manager.setPerpMarginRequirements(marketId, 0.05e18, 0.1e18);

    // trade 10 contracts, margin requirement = 10 * 1500 * 0.1 = 1500
    cash.deposit(aliceAcc, 1499e18);
    cash.deposit(bobAcc, 1499e18);

    // trade cannot go through: -1$ under collateralized
    vm.expectRevert(IStandardManager.SRM_PortfolioBelowMargin.selector);
    _tradePerpContract(aliceAcc, bobAcc, 10e18);
  }

  function testOracleContingencyOnPerps() public {
    // set oracle contingency params
    manager.setPerpMarginRequirements(marketId, 0.05e18, 0.1e18);
    manager.setOracleContingencyParams(marketId, IStandardManager.OracleContingencyParams(0.75e18, 0, 0, 0.1e18));

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

  function testNoCashMovesIfNothingToSettle() public {
    int cashBefore = _getCashBalance(aliceAcc);
    perp.mockAccountPnlAndFunding(aliceAcc, 0, 0);
    manager.settlePerpsWithIndex(aliceAcc);
    int cashAfter = _getCashBalance(aliceAcc);
    assertEq(cashAfter, cashBefore);
  }

  function testWontSettlePerpIfNoBalance() public {
    int cashBefore = _getCashBalance(aliceAcc);
    perp.mockAccountPnlAndFunding(aliceAcc, 1e18, 100e18);
    manager.settlePerpsWithIndex(aliceAcc);
    int cashAfter = _getCashBalance(aliceAcc);
    assertEq(cashAfter, cashBefore);
  }

  function testCashChangesBasedOnPerpContractPNLAndFundingValues() public {
    _tradePerpContract(aliceAcc, bobAcc, 1e18);
    int cashBefore = _getCashBalance(aliceAcc);
    perp.mockAccountPnlAndFunding(aliceAcc, 1e18, 100e18);
    manager.settlePerpsWithIndex(aliceAcc);
    int cashAfter = _getCashBalance(aliceAcc);
    assertEq(cashAfter - cashBefore, 101e18);
  }

  function testSettlePerpWithManagerData() public {
    _tradePerpContract(aliceAcc, bobAcc, 1e18);

    int cashBefore = _getCashBalance(aliceAcc);
    perp.mockAccountPnlAndFunding(aliceAcc, 0, 100e18);

    bytes memory data = abi.encode(address(manager), aliceAcc);
    IBaseManager.ManagerData[] memory allData = new IBaseManager.ManagerData[](1);
    allData[0] = IBaseManager.ManagerData({receiver: address(perpHelper), data: data});
    bytes memory managerData = abi.encode(allData);

    // only transfer 0 cash
    ISubAccounts.AssetTransfer memory transfer =
      ISubAccounts.AssetTransfer({fromAcc: aliceAcc, toAcc: bobAcc, asset: cash, subId: 0, amount: 0, assetData: ""});
    subAccounts.submitTransfer(transfer, managerData);

    int cashAfter = _getCashBalance(aliceAcc);
    assertEq(cashAfter - cashBefore, 100e18);
  }

  function testCanSettleIntoNegativeCash() public {
    _tradePerpContract(aliceAcc, bobAcc, 1e18);
    perp.mockAccountPnlAndFunding(aliceAcc, 0, -10000e18);
    manager.settlePerpsWithIndex(aliceAcc);
    assertLt(_getCashBalance(aliceAcc), 0);
  }

  function testCannotHaveNegativeCash() public {
    // assume alice has 1000 unrealized pnl (report by perp contract)
    perp.mockAccountPnlAndFunding(aliceAcc, 0, 1000e18);
    ISubAccounts.AssetTransfer memory transfer = ISubAccounts.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: cash,
      subId: 0,
      amount: 1000e18,
      assetData: ""
    });

    vm.expectRevert(IStandardManager.SRM_NoNegativeCash.selector);
    subAccounts.submitTransfer(transfer, "");
  }

  function _tradePerpContract(uint fromAcc, uint toAcc, int amount) internal {
    ISubAccounts.AssetTransfer memory transfer =
      ISubAccounts.AssetTransfer({fromAcc: fromAcc, toAcc: toAcc, asset: perp, subId: 0, amount: amount, assetData: ""});
    subAccounts.submitTransfer(transfer, "");
  }

  function _getCashBalance(uint acc) public view returns (int) {
    return subAccounts.getBalance(acc, cash, 0);
  }
}
