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

  uint expiry;

  function run() external {
    vm.startBroadcast();

    deployMockSystem();

    setupAccounts(500);

    // gas tests

    _gasSingleTransferUSDC();

    // bulk transfer gas cost
    _gasBulkTransferUSDC(100);
    _gasBulkTransferUSDC(500);

    _gasSingleTradeUSDCWithOption();

    // buck trade single account with multiple accounts
    _gasBulkTradeUSDCWithDiffOption(100);
    _gasBulkTradeUSDCWithDiffOption(500);

    // test spliting a 600x account
    _gasBulkSplitPosition(10);
    _gasBulkSplitPosition(100);

    // test settlement: the EOA already have 600 assets
    _setExpiryPrice();

    _gasSettleAccountWithMultiplePositions(100);
    _gasSettleAccountWithMultiplePositions(500);

    vm.stopBroadcast();
  }

  function _gasSingleTransferUSDC() public {
    // setup: not counting gas
    uint amount = 50e18;
    AccountStructs.AssetTransfer memory transfer = AccountStructs.AssetTransfer({
        fromAcc: ownAcc,
        toAcc: 2,
        asset: IAsset(usdcAdapter),
        subId: 0,
        amount: int(amount),
        assetData: bytes32(0)
      });

    // estimate tx cost
    uint initGas = gasleft();
    account.submitTransfer(transfer, "");
    uint endGas = gasleft();

    console.log("gas:SingleTransferUSDC:", initGas - endGas);
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

    console.log("gas:BulkTransferUSDC(", counts, "):", initGas - endGas);
  }

  function _gasSingleTradeUSDCWithOption() public {
    uint amount = 50e18;
    uint usdcAmount = 300e18;
    AccountStructs.AssetTransfer[] memory transferBatch = new AccountStructs.AssetTransfer[](2);

    uint subId = optionAdapter.addListing(1000e18, expiry, true);

    transferBatch[0] = AccountStructs.AssetTransfer({ // short option and give it to another person
      fromAcc: ownAcc,
      toAcc: 2,
      asset: IAsset(optionAdapter),
      subId: subId,
      amount: int(amount),
      assetData: bytes32(0)
    });
    transferBatch[1] = AccountStructs.AssetTransfer({ // premium
      fromAcc: 2,
      toAcc: ownAcc,
      asset: IAsset(usdcAdapter),
      subId: 0,
      amount: int(usdcAmount),
      assetData: bytes32(0)
    });

    // estimate tx cost
    uint initGas = gasleft();
    account.submitTransfers(transferBatch, "");
    uint endGas = gasleft();

   console.log("gas:SingleTradeUSDCWithOption:", initGas - endGas);
  }

  function _gasBulkTradeUSDCWithDiffOption(uint counts) public {
    // Gas test for a singel account to trade with 500 different accounts on different asset
    // which will ends up having counts+1 assets in the heldAsset array.

    // setup: not counting gas
    uint amount = 50e18;
    uint usdcAmount = 300e18;
    AccountStructs.AssetTransfer[] memory transferBatch = new AccountStructs.AssetTransfer[](counts*2);

    for(uint i = 0; i < counts; ) {

      uint subId = optionAdapter.addListing(1000e18 + (i * 10e18), expiry, true);

      transferBatch[2*i] = AccountStructs.AssetTransfer({ // short option and give it to another person
        fromAcc: ownAcc,
        toAcc: i+2, // account 1 is the EOA. start from 2
        asset: IAsset(optionAdapter),
        subId: subId,
        amount: int(amount),
        assetData: bytes32(0)
      });
      transferBatch[2*i+1] = AccountStructs.AssetTransfer({ // premium
        fromAcc: i+2,
        toAcc: ownAcc,
        asset: IAsset(usdcAdapter),
        subId: 0,
        amount: int(usdcAmount),
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

   console.log("gas:BulkTradeUSDCWithDiffOption(", counts, "):", initGas - endGas);
  }

  function _gasBulkSplitPosition(uint counts) public {
    AccountStructs.AssetBalance[] memory balances = account.getAccountBalances(ownAcc);

    if (counts > balances.length + 1) revert("don't have this many asset to settle");

    // select bunch of assets to settle
    AccountStructs.AssetTransfer[] memory transferBatch = new AccountStructs.AssetTransfer[](counts);

    for(uint i = 0; i < counts; ) {
      transferBatch[i] = AccountStructs.AssetTransfer({
        fromAcc: ownAcc,
        toAcc: i+2, // account 1 is the EOA. start from 2
        asset: IAsset(optionAdapter),
        subId: uint96(balances[i+1].subId),
        amount: (balances[i+1].balance) / 2, // send half to another account
        assetData: bytes32(0)
      });
      unchecked {
        i++;
      }
    }

    uint initGas = gasleft();
    account.submitTransfers(transferBatch, "");
    uint endGas = gasleft();

    console.log("gas:BulkSplitPosition(", counts, "):", initGas - endGas);
  }

  function _gasSettleAccountWithMultiplePositions(uint counts) public {
    AccountStructs.AssetBalance[] memory balances = account.getAccountBalances(ownAcc);

    if (counts > balances.length + 1) revert("don't have this many asset to settle");

    // select bunch of assets to settle
    AccountStructs.HeldAsset[] memory assets = new AccountStructs.HeldAsset[](counts);
    for (uint i; i < counts; i ++) {
      assets[i] = AccountStructs.HeldAsset({
        asset: IAsset(address(optionAdapter)),
        subId: uint96(balances[i+1].subId)
      });
    }
    uint initGas = gasleft();
    rm.settleAssets(ownAcc, assets);
    uint endGas = gasleft();

    console.log("gas:SettleAccountWithMultiplePositions(", counts, "):", initGas - endGas);

    // AccountStructs.AssetBalance[] memory balancesAfter = account.getAccountBalances(ownAcc);
    // console.log("\t - asset left:", balancesAfter.length);
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
    usdc.mint(msg.sender, 1000_000_000e18);
    usdc.approve(address(usdcAdapter), type(uint).max);
    usdcAdapter.deposit(ownAcc, 100_000_000e18);
    // create bunch of accounts and send to everyone
    for (uint160 i = 1; i <= amount; i++) {
      address owner = address(i);
      uint acc = account.createAccountWithApproval(owner, msg.sender, IManager(address(rm)));

      // deposit usdc for each account
      usdcAdapter.deposit(acc, 1_000e18);
    }

    expiry = block.timestamp + 1 days;

  }

  function _setExpiryPrice() public {
    vm.warp(expiry + 5);
    settlementPricer.setSettlementPrice(0, expiry); // set usdc price
    settlementPricer.setSettlementPrice(1, expiry); // set weth price
  }
}