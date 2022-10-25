// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "src/Account.sol";
import "src/interfaces/IManager.sol";
import "src/interfaces/IAccount.sol";
import "src/interfaces/AccountStructs.sol";

import "forge-std/console2.sol";

import "../account/mocks/assets/OptionToken.sol";
import "../account/mocks/assets/lending/Lending.sol";
import "../account/mocks/assets/lending/ContinuousJumpRateModel.sol";
import "../account/mocks/assets/lending/InterestRateModel.sol";
import "../account/mocks/managers/PortfolioRiskPOCManager.sol";
import "../shared/mocks/MockERC20.sol";
import "src/commitments/CommitmentAverage.sol";

contract StallAttackScript is Script {
  Account account;
  MockERC20 dai;
  Lending lending;
  OptionToken optionAdapter;
  PortfolioRiskPOCManager manager;
  TestPriceFeeds priceFeeds;
  SettlementPricer settlementPricer;
  InterestRateModel interestRateModel;

  /* Unneeded wrappers for POC Manager */
  MockERC20 weth;
  MockERC20 usdc;
  BaseWrapper wethAdapter;
  QuoteWrapper usdcAdapter;
  CommitmentAverage commitment;

  /* address setup */
  address owner = vm.addr(1);
  address node = vm.addr(2);
  address attacker = vm.addr(3);

  /**
   * @dev Assuming only 1 active node:
   *  - 
   *  - 
   *  - 
   */
  function run() external {
    _deployAccountAndStables();
    _deployOptionAndManager();
    _mintDai(node, 5e18);
    _mintDai(owner, 5e18);
    _mintDai(attacker, 5e18);
    _mintDai(node, 5e18);

    // _setupParams(1500e18);
    
    // /* mint dai and deposit to attacker account */
    // vm.startBroadcast(owner);
    // uint attackerAccId = account.createAccount(attacker, IManager(address(manager)));
    // vm.stopBroadcast();

    // _depositToAccount(attacker, attackerAccId, 1_000_000e18);

    // /* deposit to node */
    // _depositToNode(100_000e18);
  }

  function _depositToNode(uint amount) public {
    _mintDai(node, amount);
    // setup: not counting gas
    vm.startBroadcast(node);

    dai.approve(address(commitment), type(uint).max);

    commitment.deposit(amount); // deposit $50k DAI

    vm.stopBroadcast();
  }

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
    // optionAdapter = new OptionToken(account, PriceFeeds(address(priceFeeds)), settlementPricer, 1);
    // _addListings();

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

    // /* setup commitment contract */
    commitment = new CommitmentAverage(address(account), address(manager), address(lending), address(dai));
    vm.stopBroadcast();
  }

  function _setupParams(uint wethPrice) internal {
    vm.startBroadcast(owner);

    uint wethFeedId = 1;
    priceFeeds.setSpotForFeed(wethFeedId, wethPrice);

    PortfolioRiskPOCManager.Scenario[] memory scenarios = new PortfolioRiskPOCManager.Scenario[](1);
    scenarios[0] = PortfolioRiskPOCManager.Scenario({spotShock: uint(85e16), ivShock: 10e18});

    manager.setScenarios(scenarios);

    vm.stopBroadcast();
  }

  function _addListings() public {
    uint72[7] memory strikes =
      [1000e18, 1300e18, 1400e18, 1500e18, 1600e18, 1700e18, 2000e18];

    uint32[7] memory expiries = [1 weeks, 2 weeks, 4 weeks, 8 weeks, 12 weeks, 26 weeks, 52 weeks];
    for (uint s = 0; s < strikes.length; s++) {
      for (uint e = 0; e < expiries.length; e++) {
        optionAdapter.addListing(strikes[s], expiries[e], true);
      }
    }
  }

  function _mintDai(address user, uint amount) public {
    vm.startBroadcast(owner);
    dai.mint(user, amount);
    vm.stopBroadcast();
  }
}
