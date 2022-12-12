// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/Account.sol";
import "src/interfaces/IManager.sol";
import "src/interfaces/IAccount.sol";
import "src/interfaces/AccountStructs.sol";

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../mocks/assets/OptionToken.sol";
import "../mocks/assets/BaseWrapper.sol";
import "../mocks/assets/QuoteWrapper.sol";
import "../mocks/assets/lending/Lending.sol";
import "../mocks/assets/lending/ContinuousJumpRateModel.sol";
import "../mocks/assets/lending/InterestRateModel.sol";
import "../mocks/managers/PortfolioRiskPOCManager.sol";
import "../../shared/mocks/MockERC20.sol";

abstract contract AccountPOCHelper is Test {
  Account account;
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
    account = new Account("Lyra Margin Accounts", "LyraMarginNFTs");

    /* Feeds | Oracles | Vol Engine */
    priceFeeds = new TestPriceFeeds();

    /* Wrappers */
    usdc = new MockERC20("usdc", "USDC");
    usdcAdapter = new QuoteWrapper(IERC20(usdc), account, priceFeeds, 0);
    weth = new MockERC20("wrapped eth", "wETH");
    wethAdapter = new BaseWrapper(IERC20(weth), IAccount(address(account)), priceFeeds, 1);

    /* Lending */
    dai = new MockERC20("dai", "DAI");
    // starts at 5%, increases to 10% at 50% util, then grows by 2% for every 10% util increase
    interestRateModel = new ContinuousJumpRateModel(5e16, 1e17, 2e17, 5e17);
    daiLending = new Lending(IERC20(dai), IAccount(address(account)), interestRateModel);

    /* Options */
    settlementPricer = new SettlementPricer(PriceFeeds(priceFeeds));
    optionAdapter = new OptionToken(account, priceFeeds, settlementPricer, 1);

    /* Risk Manager */
    rm =
    new PortfolioRiskPOCManager(IAccount(address(account)), PriceFeeds(priceFeeds), usdcAdapter, wethAdapter, optionAdapter, daiLending);
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
    AccountStructs.AssetTransfer memory optionTransfer = AccountStructs.AssetTransfer({
      fromAcc: shortAcc,
      toAcc: longAcc,
      asset: IAsset(optionAdapter),
      subId: optionSubId,
      amount: int(amount),
      assetData: bytes32(0)
    });

    AccountStructs.AssetTransfer memory premiumTransfer = AccountStructs.AssetTransfer({
      fromAcc: longAcc,
      toAcc: shortAcc,
      asset: IAsset(usdcAdapter),
      subId: 0,
      amount: int(premium),
      assetData: bytes32(0)
    });

    AccountStructs.AssetTransfer[] memory transferBatch = new AccountStructs.AssetTransfer[](2);
    transferBatch[0] = optionTransfer;
    transferBatch[1] = premiumTransfer;

    account.submitTransfers(transferBatch, "");
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
    accountId = account.createAccount(user, IManager(rm));
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
    accountId = account.createAccount(user, IManager(rm));
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
    AccountStructs.AssetAllowance[] memory assetAllowances = new AccountStructs.AssetAllowance[](2);
    assetAllowances[0] =
      AccountStructs.AssetAllowance({asset: IAsset(optionAdapter), positive: type(uint).max, negative: type(uint).max});
    assetAllowances[1] =
      AccountStructs.AssetAllowance({asset: IAsset(usdcAdapter), positive: type(uint).max, negative: type(uint).max});

    account.setAssetAllowances(ownerAcc, delegate, assetAllowances);
    vm.stopPrank();
  }

  function setupMaxSingleAssetAllowance(address ownerAdd, uint ownerAcc, address delegate, IAsset asset) internal {
    vm.startPrank(ownerAdd);
    AccountStructs.AssetAllowance[] memory assetAllowances = new AccountStructs.AssetAllowance[](2);
    assetAllowances[0] =
      AccountStructs.AssetAllowance({asset: IAsset(asset), positive: type(uint).max, negative: type(uint).max});

    account.setAssetAllowances(ownerAcc, delegate, assetAllowances);
    vm.stopPrank();
  }

  function tradeOptionWithUSDC(uint fromAcc, uint toAcc, uint optionAmount, uint usdcAmount, uint optionSubId) internal {
    AccountStructs.AssetTransfer memory optionTransfer = AccountStructs.AssetTransfer({
      fromAcc: fromAcc,
      toAcc: toAcc,
      asset: IAsset(optionAdapter),
      subId: optionSubId,
      amount: int(optionAmount),
      assetData: bytes32(0)
    });

    AccountStructs.AssetTransfer memory premiumTransfer = AccountStructs.AssetTransfer({
      fromAcc: toAcc,
      toAcc: fromAcc,
      asset: IAsset(usdcAdapter),
      subId: 0,
      amount: int(usdcAmount),
      assetData: bytes32(0)
    });

    AccountStructs.AssetTransfer[] memory transferBatch = new AccountStructs.AssetTransfer[](2);
    transferBatch[0] = optionTransfer;
    transferBatch[1] = premiumTransfer;

    account.submitTransfers(transferBatch, "");
  }

  // add in a function prefixed with test here to prevent coverage to pick it up.
  function testCoverageChill() public {}
}
