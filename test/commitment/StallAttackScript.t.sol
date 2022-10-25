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

contract StallAttackScript is Script {
  Account account;
  MockERC20 dai;
  Lending daiLending;
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

  /**
   * @dev Assuming only 1 active node:
   *  - 
   *  - 
   *  - 
   */
  function run() external {
    vm.startBroadcast();

    _deployMockSystem();

    _setupParams(1500e18);

    // gas tests
    _placeDeposit();

    vm.stopBroadcast();
  }

  function _placeDeposit() public {
    // setup: not counting gas
    console.log("placeholder...");
  }

  /// @dev deploy mock system
  function _deployMockSystem() public {
    /* Base Layer */
    account = new Account("Lyra Margin Accounts", "LyraMarginNFTs");

    /* Feeds | Oracles | Vol Engine */
    priceFeeds = new TestPriceFeeds();

    /* Wrappers & Lending*/
    dai = new MockERC20("dai", "DAI");
    interestRateModel = new ContinuousJumpRateModel(5e16, 1e17, 2e17, 5e17);
    daiLending = new Lending(IERC20(dai), IAccount(address(account)), interestRateModel);

    /* Unneeded wrappers for POC manager */
    usdc = new MockERC20("usdc", "USDC");
    usdcAdapter = new QuoteWrapper(IERC20(usdc), account, priceFeeds, 0);
    weth = new MockERC20("wrapped eth", "wETH");
    wethAdapter = new BaseWrapper(IERC20(weth), IAccount(address(account)), priceFeeds, 1);

    // optionAsset: not allow deposit, can be negative
    settlementPricer = new SettlementPricer(PriceFeeds(priceFeeds));
    optionAdapter = new OptionToken(account, priceFeeds, settlementPricer, 1);

    /* Risk Manager */
    manager = new PortfolioRiskPOCManager(
      IAccount(address(account)), 
      PriceFeeds(priceFeeds), 
      usdcAdapter, 
      wethAdapter, 
      optionAdapter, 
      daiLending
    );
    optionAdapter.setManagerAllowed(IManager(manager), true);
    daiLending.setManagerAllowed(IManager(manager), true);
  }

  function _setupParams(uint wethPrice) internal {
    uint wethFeedId = 1;
    priceFeeds.setSpotForFeed(wethFeedId, wethPrice);

    PortfolioRiskPOCManager.Scenario[] memory scenarios = new PortfolioRiskPOCManager.Scenario[](1);
    scenarios[0] = PortfolioRiskPOCManager.Scenario({spotShock: uint(85e16), ivShock: 10e18});

    manager.setScenarios(scenarios);
  }

  // function _setupAccounts(uint amount) internal {
  //   // create 1 account for EOA
  //   ownAcc = account.createAccount(msg.sender, IManager(address(manager)));
  //   usdc.mint(msg.sender, 1000_000_000e18);
  //   usdc.approve(address(usdcAdapter), type(uint).max);
  //   usdcAdapter.deposit(ownAcc, 0, 100_000_000e18);
  //   // create bunch of accounts and send to everyone
  //   for (uint160 i = 1; i <= amount; i++) {
  //     address owner = address(i);
  //     uint acc = account.createAccountWithApproval(owner, msg.sender, IManager(address(manager)));

  //     // deposit usdc for each account
  //     usdcAdapter.deposit(acc, 0, 1_000e18);
  //   }

  //   expiry = block.timestamp + 1 days;
  // }
}
