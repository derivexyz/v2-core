// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "src/interfaces/AccountStructs.sol";

import "../mocks/assets/OptionToken.sol";
import "../mocks/assets/BaseWrapper.sol";
import "../mocks/assets/QuoteWrapper.sol";
import "../mocks/assets/lending/Lending.sol";
import "../mocks/assets/lending/ContinuousJumpRateModel.sol";
import "../mocks/assets/lending/InterestRateModel.sol";
import "../mocks/managers/PortfolioRiskPOCManager.sol";
import "../../shared/mocks/MockERC20.sol";

contract AccountGasScript is Script {

  uint ownAcc;
  
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

  function run() external {
    vm.startBroadcast();

    deployMockSystem();

    uint counts = 500;

    setupAccounts(counts);

    // bulk transfer gas cost
    _gasBulkTransferUSDC(counts);

    // buck trade

    vm.stopBroadcast();
  }

  function _gasBulkTransferUSDC(uint counts) public {
    // setup: not counting gas
    uint amount = 50e18;
    AccountStructs.AssetTransfer[] memory transferBatch = new AccountStructs.AssetTransfer[](counts);

    for(uint i = 0; i < counts; ) {
      transferBatch[i] = AccountStructs.AssetTransfer({
        fromAcc: ownAcc,
        toAcc: i+2, // account 1 is the EOA. start from 2
        asset: IAsset(usdcAdapter),
        subId: 0,
        amount: int(amount),
        assetData: bytes32(0)
      });
      unchecked {
        i++;
      }
    }

    // estimate tx cost
    uint initGas = gasleft();
    account.submitTransfers(transferBatch, "");
    uint endGas = gasleft();

    console.log("gas:BulkTransferUSDC(500)", initGas - endGas);
  }

  /// @dev deploy mock system
  function deployMockSystem() public {
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
    rm = new PortfolioRiskPOCManager(IAccount(address(account)), PriceFeeds(priceFeeds), usdcAdapter, wethAdapter, optionAdapter, daiLending);
    usdcAdapter.setManagerAllowed(IManager(rm), true);
    optionAdapter.setManagerAllowed(IManager(rm), true);
    daiLending.setManagerAllowed(IManager(rm), true);
    
    priceFeeds.setSpotForFeed(0, 1e18);
    priceFeeds.setSpotForFeed(1, 1500e18);

    PortfolioRiskPOCManager.Scenario[] memory scenarios = new PortfolioRiskPOCManager.Scenario[](1);
    scenarios[0] = PortfolioRiskPOCManager.Scenario({spotShock: uint(85e16), ivShock: 10e18});

    rm.setScenarios(scenarios);
  }

  function setupAccounts(uint amount) public {

    // create 1 account for EOA
    ownAcc = account.createAccount(msg.sender, IManager(address(rm)));
    usdc.mint(msg.sender, 100_000_000e18);
    usdc.approve(address(usdcAdapter), type(uint).max);
    usdcAdapter.deposit(ownAcc, 100_000_000e18);
    // create bunch of accounts and send to everyone
    for (uint160 i = 1; i <= amount; i++) {
      address owner = address(i);
      account.createAccountWithApproval(owner, msg.sender, IManager(address(rm)));
    }

  }
}