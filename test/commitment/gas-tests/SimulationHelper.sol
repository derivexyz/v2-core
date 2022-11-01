// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "src/Account.sol";
import "src/interfaces/IManager.sol";
import "src/interfaces/IAccount.sol";
import "src/interfaces/AccountStructs.sol";

import "forge-std/console2.sol";

import "../../account/mocks/assets/OptionToken.sol";
import "../../shared/mocks/MockAsset.sol";
import "../../account/mocks/assets/lending/Lending.sol";
import "../../account/mocks/assets/lending/ContinuousJumpRateModel.sol";
import "../../account/mocks/assets/lending/InterestRateModel.sol";
import "../../account/mocks/managers/PortfolioRiskPOCManager.sol";
import "../../shared/mocks/MockERC20.sol";

// run  with `forge script StallAttackScript --fork-url http://localhost:8545` against anvil
// OptionToken deployment fails when running outside of localhost

contract SimulationHelper is Script {
  Account account;
  MockERC20 dai;
  Lending lending;
  // MockAsset optionAdapter;
  OptionToken optionAdapter;
  PortfolioRiskPOCManager manager;
  TestPriceFeeds priceFeeds;
  SettlementPricer settlementPricer;
  InterestRateModel interestRateModel;
  uint usdcFeedId = 0;
  uint wethFeedId = 1;

  /* Unneeded wrappers for POC Manager */
  MockERC20 weth;
  MockERC20 usdc;
  BaseWrapper wethAdapter;
  QuoteWrapper usdcAdapter;

  /* address setup */
  address owner = vm.addr(1);


  function _depositToAccount(address user, uint acc, uint amount) internal {
    // mint DAI
    _mintDai(user, amount);

    // deposit to lending asset
    vm.startBroadcast(user);
    dai.approve(address(lending), type(uint).max);
    lending.deposit(acc, amount);
    vm.stopBroadcast();
  }

  /// @dev deploy mock system
  function _deployAccountAndStables() public {
    vm.startBroadcast(owner);

    /* Base Layer */
    account = new Account("Lyra Margin Accounts", "LyraMarginNFTs");

    /* Feeds | Oracles | Vol Engine */
    priceFeeds = new TestPriceFeeds();

    /* Wrappers & Lending*/
    dai = new MockERC20("dai", "DAI");
    interestRateModel = new ContinuousJumpRateModel(5e16, 1e17, 2e17, 5e17);
    lending = new Lending(IERC20(dai), IAccount(address(account)), interestRateModel);

    /* Unneeded wrappers for POC manager */
    usdc = new MockERC20("usdc", "USDC");
    usdcAdapter = new QuoteWrapper(IERC20(usdc), account, priceFeeds, 0);
    weth = new MockERC20("wrapped eth", "wETH");
    wethAdapter = new BaseWrapper(IERC20(weth), IAccount(address(account)), priceFeeds, 1);

    vm.stopBroadcast();
  }

  function _deployOptionAndManager() public {
    vm.startBroadcast(owner);

    /* Option Asset */
    settlementPricer = new SettlementPricer(priceFeeds);

    optionAdapter = new OptionToken(
      IAccount(address(account)), 
      PriceFeeds(address(priceFeeds)), 
      settlementPricer, 
      wethFeedId
    );

    /* Risk Manager */
    manager = new PortfolioRiskPOCManager(
      IAccount(address(account)), 
      PriceFeeds(priceFeeds), 
      usdcAdapter, 
      wethAdapter, 
      OptionToken(address(0)), // optionAdapter, 
      lending
    );
    // optionAdapter.setManagerAllowed(IManager(manager), true);
    lending.setManagerAllowed(IManager(manager), true);
    vm.stopBroadcast();
  }

  function _setupParams(uint wethPrice) internal {
    vm.startBroadcast(owner);

    priceFeeds.setSpotForFeed(wethFeedId, wethPrice);
    priceFeeds.setSpotForFeed(usdcFeedId, 1e18);

    PortfolioRiskPOCManager.Scenario[] memory scenarios = new PortfolioRiskPOCManager.Scenario[](1);
    scenarios[0] = PortfolioRiskPOCManager.Scenario({spotShock: uint(85e16), ivShock: 10e18});

    manager.setScenarios(scenarios);

    vm.stopBroadcast();
  }

  function _mintDai(address user, uint amount) public {
    vm.startBroadcast(owner);
    dai.mint(user, amount);
    vm.stopBroadcast();
  }
}
