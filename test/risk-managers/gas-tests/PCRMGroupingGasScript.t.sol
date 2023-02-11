pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "test/feeds/mocks/MockV3Aggregator.sol";
import "src/feeds/ChainlinkSpotFeeds.sol";
import "src/assets/Option.sol";
import "src/risk-managers/PCRM.sol";
import "src/assets/CashAsset.sol";
import "src/assets/InterestRateModel.sol";
import "src/Accounts.sol";
import "src/interfaces/IManager.sol";
import "src/interfaces/IAsset.sol";
import "src/interfaces/AccountStructs.sol";
import "test/shared/mocks/MockManager.sol";
import "test/shared/mocks/MockERC20.sol";
import "test/risk-managers/mocks/MockDutchAuction.sol";
import "test/risk-managers/mocks/MockSpotJumpOracle.sol";

contract PCRMGroupingGasScript is Script {
  Accounts account;
  PCRM pcrm;

  ChainlinkSpotFeeds spotFeeds;
  MockV3Aggregator aggregator;
  Option option;
  MockDutchAuction auction;
  CashAsset cash;
  MockSpotJumpOracle spotJumpOracle;

  address alice = address(0xaa);
  address bob = address(0xbb);
  uint aliceAcc;
  uint bobAcc;

  function run() external {
    vm.startBroadcast();
    _setupFeeds();
    _setupBaseLayer();
    vm.stopBroadcast();

    vm.startBroadcast(alice);
    aliceAcc = account.createAccount(alice, IManager(pcrm));
    bobAcc = account.createAccount(bob, IManager(pcrm));
    vm.stopBroadcast();

    vm.startBroadcast(bob);
    account.approve(alice, bobAcc);
    vm.stopBroadcast();

    vm.startBroadcast(alice);

    // gas tests
    _gasSingleOption();
    _gasMaxAssets();

    vm.stopBroadcast();
  }

  function _gasSingleOption() public {
    AccountStructs.AssetTransfer memory transfer = AccountStructs.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAsset(option),
      subId: 1,
      amount: 1e18,
      assetData: ""
    });
    account.submitTransfer(transfer, "");

    // estimate tx cost
    uint initGas = gasleft();

    pcrm.getPortfolio(aliceAcc);

    console.log("gas:singleAsset:", initGas - gasleft());
  }

  function _gasMaxAssets() public {
    AccountStructs.AssetTransfer[] memory assetTransfers = _composeMaxTransfers();

    // create account
    for (uint i; i < assetTransfers.length; i++) {
      // todo [Vlad]: crashes somewhere here
      account.submitTransfer(assetTransfers[i], "");
    }

    // estimate gas for only getting balances
    uint initGas = gasleft();
    account.getAccountBalances(aliceAcc);
    uint endGas = gasleft();
    console.log("gas: getting 64 asset balances from account:", initGas - endGas);

    // estimate gas for grouping + getting balances
    initGas = gasleft();
    pcrm.getPortfolio(aliceAcc);
    console.log("gas: grouping 64 assets in PCRM:", initGas - gasleft());
  }

  function _setupFeeds() public {
    aggregator = new MockV3Aggregator(18, 1000e18);
    spotFeeds = new ChainlinkSpotFeeds();
    spotFeeds.addFeed("ETH/USD", address(aggregator), 1 hours);
    aggregator.updateRoundData(1, 1000e18, block.timestamp, block.timestamp, 1);
  }

  function _setupBaseLayer() public {
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    auction = new MockDutchAuction();

    option = new Option(account, address(0), 0);
    MockERC20 stable = new MockERC20("mock", "MOCK");

    // interest rate model
    uint minRate = 0.06 * 1e18;
    uint rateMultiplier = 0.2 * 1e18;
    uint highRateMultiplier = 0.4 * 1e18;
    uint optimalUtil = 0.6 * 1e18;
    InterestRateModel rateModel = new InterestRateModel(minRate, rateMultiplier, highRateMultiplier, optimalUtil);

    cash = new CashAsset(IAccounts(account), IERC20Metadata(address(stable)), rateModel, 0, address(auction));

    spotJumpOracle = new MockSpotJumpOracle();

    pcrm = new PCRM(
      account,
      ISpotFeeds(address(spotFeeds)),
      cash,
      option,
      address(auction),
      ISpotJumpOracle(address(spotJumpOracle))
    );

    pcrm.setParams(
      PCRM.SpotShockParams({
        upInitial: 1.25e18,
        downInitial: 0.75e18,
        upMaintenance: 1.1e18,
        downMaintenance: 0.9e18,
        timeSlope: 1e18,
        spotJumpMultipleSlope: 5e18,
        spotJumpMultipleLookback: 1 days
      }),
      PCRM.VolShockParams({
        minVol: 1e18,
        maxVol: 3e18,
        timeA: 30 days,
        timeB: 90 days,
        spotJumpMultipleSlope: 5e18,
        spotJumpMultipleLookback: 1 days
      }),
      PCRM.PortfolioDiscountParams({
        maintenance: 0.9e18, // 90%
        initial: 0.8e18, // 80%
        riskFreeRate: 0.1e18 // 10%
      })
    );
  }

  function _composeMaxTransfers() public view returns (AccountStructs.AssetTransfer[] memory assetTransfers) {
    //
    uint max_strikes = pcrm.MAX_STRIKES();
    assetTransfers = new AccountStructs.AssetTransfer[](max_strikes);

    //
    uint baseExpiry = block.timestamp;
    uint baseStrike = 0;
    for (uint i; i < max_strikes; i++) {
      uint newSubId = OptionEncoding.toSubId(baseExpiry, baseStrike + i * 10e18, true);
      assetTransfers[i] = AccountStructs.AssetTransfer({
        fromAcc: aliceAcc,
        toAcc: bobAcc,
        asset: IAsset(option),
        subId: newSubId,
        amount: 1e18,
        assetData: ""
      });
    }

    return assetTransfers;
  }

  function test() public {}
}
