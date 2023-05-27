// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "src/SubAccounts.sol";
import {IManager} from "src/interfaces/IManager.sol";
import {ISubAccounts} from "src/interfaces/ISubAccounts.sol";

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../mocks/assets/OptionToken.sol";
import "../mocks/assets/BaseWrapper.sol";
import "../mocks/assets/QuoteWrapper.sol";
import "../mocks/assets/lending/Lending.sol";
import "../mocks/assets/lending/ContinuousJumpRateModel.sol";
import "../mocks/assets/lending/InterestRateModel.sol";
import "../mocks/managers/PortfolioRiskPOCManager.sol";
import "../mocks/assets/lending/Lending.sol";

import "../../shared/mocks/MockERC20.sol";

abstract contract AccountPOCHelper is Test {
  SubAccounts subAccounts;
  MockERC20 weth;
  MockERC20 usdc;
  MockERC20 dai;
  BaseWrapper wethAdapter;
  QuoteWrapper usdcAdapter;
  Lending daiLending;
  OptionToken optionAdapter;
  TestPriceFeeds priceFeeds;
  SettlementPricer settlementPricer;
  InterestRateModel interestRateModel;
  PortfolioRiskPOCManager rm;

  uint usdcFeedId = 0;
  uint wethFeedId = 1;

  address owner = vm.addr(1);
  address alice = vm.addr(2);
  address bob = vm.addr(3);
  address charlie = vm.addr(4);
  address david = vm.addr(5);

  function deployPRMSystem() public {
    vm.startPrank(owner);

    /* Base Layer */
    subAccounts = new SubAccounts("Lyra Margin Accounts", "LyraMarginNFTs");

    /* Feeds | Oracles | Vol Engine */
    priceFeeds = new TestPriceFeeds();

    /* Wrappers */
    usdc = new MockERC20("usdc", "USDC");
    usdcAdapter = new QuoteWrapper(IERC20(usdc), subAccounts, priceFeeds, 0);
    weth = new MockERC20("wrapped eth", "wETH");
    wethAdapter = new BaseWrapper(IERC20(weth), subAccounts, priceFeeds, 1);

    /* Lending */
    dai = new MockERC20("dai", "DAI");
    // starts at 5%, increases to 10% at 50% util, then grows by 2% for every 10% util increase
    interestRateModel = new ContinuousJumpRateModel(5e16, 1e17, 2e17, 5e17);
    daiLending = new Lending(IERC20(dai), subAccounts, interestRateModel);

    /* Options */
    settlementPricer = new SettlementPricer(PriceFeeds(priceFeeds));
    optionAdapter = new OptionToken(subAccounts, priceFeeds, settlementPricer, 1);

    /* Risk Manager */
    rm =
    new PortfolioRiskPOCManager(subAccounts, PriceFeeds(priceFeeds), usdcAdapter, wethAdapter, optionAdapter, daiLending);
    usdcAdapter.setManagerAllowed(IManager(rm), true);
    optionAdapter.setManagerAllowed(IManager(rm), true);
    daiLending.setManagerAllowed(IManager(rm), true);

    vm.stopPrank();
  }

  function setPrices(uint usdcPrice, uint wethPrice) public {
    vm.startPrank(owner);
    priceFeeds.setSpotForFeed(usdcFeedId, usdcPrice);
    priceFeeds.setSpotForFeed(wethFeedId, wethPrice);
    vm.stopPrank();
  }

  function setSettlementPrice(uint expiry) public {
    vm.startPrank(owner);
    settlementPricer.setSettlementPrice(wethFeedId, expiry);
    settlementPricer.setSettlementPrice(usdcFeedId, expiry);
    vm.stopPrank();
  }

  function setScenarios(PortfolioRiskPOCManager.Scenario[] memory scenarios) public {
    vm.startPrank(owner);
    rm.setScenarios(scenarios);
    vm.stopPrank();
  }

  function tradeCallOption(uint longAcc, uint shortAcc, uint amount, uint premium, uint optionSubId) public {
    ISubAccounts.AssetTransfer memory optionTransfer = ISubAccounts.AssetTransfer({
      fromAcc: shortAcc,
      toAcc: longAcc,
      asset: IAsset(optionAdapter),
      subId: optionSubId,
      amount: int(amount),
      assetData: bytes32(0)
    });

    ISubAccounts.AssetTransfer memory premiumTransfer = ISubAccounts.AssetTransfer({
      fromAcc: longAcc,
      toAcc: shortAcc,
      asset: IAsset(usdcAdapter),
      subId: 0,
      amount: int(premium),
      assetData: bytes32(0)
    });

    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](2);
    transferBatch[0] = optionTransfer;
    transferBatch[1] = premiumTransfer;

    subAccounts.submitTransfers(transferBatch, "");
  }

  function setupDefaultScenarios() public {
    vm.startPrank(owner);
    uint[5] memory shocks = [uint(50e16), uint(75e16), uint(1e18), uint(125e16), uint(150e16)];

    PortfolioRiskPOCManager.Scenario[] memory scenarios = new PortfolioRiskPOCManager.Scenario[](5);
    for (uint i; i < shocks.length; i++) {
      scenarios[i] = PortfolioRiskPOCManager.Scenario({spotShock: shocks[i], ivShock: 100e18});
    }

    PortfolioRiskPOCManager(rm).setScenarios(scenarios);
    vm.stopPrank();
  }

  function createAccountAndDepositUSDC(address user, uint balance) public returns (uint accountId) {
    vm.startPrank(user);
    accountId = subAccounts.createAccount(user, IManager(rm));
    vm.stopPrank();

    if (balance > 0) {
      vm.startPrank(owner);
      usdc.mint(user, balance);
      vm.stopPrank();

      vm.startPrank(user);
      usdc.approve(address(usdcAdapter), type(uint).max);
      usdcAdapter.deposit(accountId, balance);
      vm.stopPrank();
    }
    return accountId;
  }

  function createAccountAndDepositDaiLending(address user, uint balance) public returns (uint accountId) {
    vm.startPrank(user);
    accountId = subAccounts.createAccount(user, IManager(rm));
    vm.stopPrank();

    if (balance > 0) {
      vm.startPrank(owner);
      dai.mint(user, balance);
      vm.stopPrank();

      vm.startPrank(user);
      dai.approve(address(daiLending), type(uint).max);
      daiLending.deposit(accountId, balance);
      vm.stopPrank();
    }
    return accountId;
  }

  function setupMaxAssetAllowancesForAll(address ownerAdd, uint ownerAcc, address delegate) internal {
    vm.startPrank(ownerAdd);
    IAllowances.AssetAllowance[] memory assetAllowances = new IAllowances.AssetAllowance[](2);
    assetAllowances[0] =
      IAllowances.AssetAllowance({asset: IAsset(optionAdapter), positive: type(uint).max, negative: type(uint).max});
    assetAllowances[1] =
      IAllowances.AssetAllowance({asset: IAsset(usdcAdapter), positive: type(uint).max, negative: type(uint).max});

    subAccounts.setAssetAllowances(ownerAcc, delegate, assetAllowances);
    vm.stopPrank();
  }

  function setupMaxSingleAssetAllowance(address ownerAdd, uint ownerAcc, address delegate, IAsset asset) internal {
    vm.startPrank(ownerAdd);
    IAllowances.AssetAllowance[] memory assetAllowances = new IAllowances.AssetAllowance[](2);
    assetAllowances[0] =
      IAllowances.AssetAllowance({asset: IAsset(asset), positive: type(uint).max, negative: type(uint).max});

    subAccounts.setAssetAllowances(ownerAcc, delegate, assetAllowances);
    vm.stopPrank();
  }

  function tradeOptionWithUSDC(uint fromAcc, uint toAcc, uint optionAmount, uint usdcAmount, uint optionSubId) internal {
    ISubAccounts.AssetTransfer memory optionTransfer = ISubAccounts.AssetTransfer({
      fromAcc: fromAcc,
      toAcc: toAcc,
      asset: IAsset(optionAdapter),
      subId: optionSubId,
      amount: int(optionAmount),
      assetData: bytes32(0)
    });

    ISubAccounts.AssetTransfer memory premiumTransfer = ISubAccounts.AssetTransfer({
      fromAcc: toAcc,
      toAcc: fromAcc,
      asset: IAsset(usdcAdapter),
      subId: 0,
      amount: int(usdcAmount),
      assetData: bytes32(0)
    });

    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](2);
    transferBatch[0] = optionTransfer;
    transferBatch[1] = premiumTransfer;

    subAccounts.submitTransfers(transferBatch, "");
  }

  // add in a function prefixed with test here to prevent coverage from picking it up.
  function testCoverageChill() public {}
}
