// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/Account.sol";
import "src/interfaces/IAbstractManager.sol";

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../mocks/assets/OptionToken.sol";
import "../mocks/assets/BaseWrapper.sol";
import "../mocks/assets/QuoteWrapper.sol";
import "../mocks/PortfolioRiskManager.sol";
import "../mocks/TestERC20.sol";

abstract contract LyraHelper is Test {
  Account account;
  TestERC20 weth;
  TestERC20 usdc;
  BaseWrapper wethAdapter;
  QuoteWrapper usdcAdapter;
  OptionToken optionAdapter;
  TestPriceFeeds priceFeeds;
  SettlementPricer settlementPricer;
  PortfolioRiskManager rm;

  uint usdcFeedId = 0;
  uint wethFeedId = 1;

  address owner = vm.addr(1);
  address alice = vm.addr(2);
  address bob = vm.addr(3);
  address charlie = vm.addr(4);
  address david = vm.addr(5);

  function deployPRMSystem() public {
    vm.startPrank(owner);

    account = new Account("Lyra Margin Accounts", "LyraMarginNFTs");

    weth = new TestERC20("wrapped eth", "wETH");
    usdc = new TestERC20("usdc", "USDC");

    priceFeeds = new TestPriceFeeds();
    settlementPricer = new SettlementPricer(PriceFeeds(priceFeeds));

    usdcAdapter = new QuoteWrapper(IERC20(usdc), account, priceFeeds, 0);

    wethAdapter = new BaseWrapper(IERC20(weth), account, priceFeeds, 1);

    optionAdapter = new OptionToken(account, priceFeeds, settlementPricer, 1);

    rm = new PortfolioRiskManager(account, PriceFeeds(priceFeeds), usdcAdapter, 0, wethAdapter, 1, optionAdapter);

    usdcAdapter.setRiskModelAllowed(IAbstractManager(rm), true);
    optionAdapter.setRiskModelAllowed(IAbstractManager(rm), true);
    vm.stopPrank();
  }

  function setPrices(uint usdcPrice, uint wethPrice) public {
    vm.startPrank(owner);
    priceFeeds.setSpotForFeed(usdcFeedId, usdcPrice);
    priceFeeds.setSpotForFeed(wethFeedId, wethPrice);
    vm.stopPrank();
  }

  function setScenarios(PortfolioRiskManager.Scenario[] memory scenarios) public {
    vm.startPrank(owner);
    rm.setScenarios(scenarios);
    vm.stopPrank();
  }

  function tradeCallOption(uint longAcc, uint shortAcc, uint amount, uint premium, uint optionSubId) public {
    IAccount.AssetTransfer memory optionTransfer = IAccount.AssetTransfer({
      fromAcc: shortAcc,
      toAcc: longAcc,
      asset: IAbstractAsset(optionAdapter),
      subId: optionSubId,
      amount: int(amount),
      assetData: bytes32(0)
    });

    IAccount.AssetTransfer memory premiumTransfer = IAccount.AssetTransfer({
      fromAcc: longAcc,
      toAcc: shortAcc,
      asset: IAbstractAsset(usdcAdapter),
      subId: 0,
      amount: int(premium),
      assetData: bytes32(0)
    });

    IAccount.AssetTransfer[] memory transferBatch = new IAccount.AssetTransfer[](2);
    transferBatch[0] = optionTransfer;
    transferBatch[1] = premiumTransfer;

    account.submitTransfers(transferBatch, "");
  }

  function setupDefaultScenarios() public {
    vm.startPrank(owner);
    uint[5] memory shocks = [uint(50e16), uint(75e16), uint(1e18), uint(125e16), uint(150e16)];

    PortfolioRiskManager.Scenario[] memory scenarios = new PortfolioRiskManager.Scenario[](5);
    for (uint i; i < shocks.length; i++) {
      scenarios[i] = PortfolioRiskManager.Scenario({spotShock: shocks[i], ivShock: 100e18});
    }

    PortfolioRiskManager(rm).setScenarios(scenarios);
    vm.stopPrank();
  }

  function createAccountAndDepositUSDC(address user, uint balance) public returns (uint accountId) {
    vm.startPrank(user);
    accountId = account.createAccount(user, IAbstractManager(rm));
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

  function setupAssetAllowances(address ownerAdd, uint ownerAcc, address delegate) internal {
    vm.startPrank(ownerAdd);
    IAbstractAsset[] memory assets = new IAbstractAsset[](2);
    assets[0] = IAbstractAsset(optionAdapter);
    assets[1] = IAbstractAsset(usdcAdapter);
    uint[] memory posAllowances = new uint[](2);
    uint[] memory negAllowances = new uint[](2);
    posAllowances[0] = type(uint).max;
    posAllowances[1] = type(uint).max;
    negAllowances[0] = type(uint).max;
    negAllowances[1] = type(uint).max;

    account.setAssetAllowances(ownerAcc, delegate, assets, posAllowances, negAllowances);
    vm.stopPrank();
  }
}
