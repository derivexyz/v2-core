pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "test/feeds/mocks/MockV3Aggregator.sol";
import "src/feeds/ChainlinkSpotFeeds.sol";
import "src/assets/Option.sol";
import "src/risk-managers/PCRM.sol";
import "src/assets/CashAsset.sol";
import "src/Accounts.sol";
import "src/interfaces/IManager.sol";
import "src/interfaces/IAsset.sol";
import "src/interfaces/AccountStructs.sol";
import "test/shared/mocks/MockManager.sol";
import "test/shared/mocks/MockERC20.sol";
import "test/risk-managers/mocks/MockDutchAuction.sol";

contract PCRMGroupingGasScript is Script {
  Accounts account;
  PCRM pcrm;

  ChainlinkSpotFeeds spotFeeds;
  MockV3Aggregator aggregator;
  Option option;
  MockDutchAuction auction;
  CashAsset cash;

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

    pcrm.getGroupedOptions(aliceAcc);

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
    console.log("gas: getting 128 asset balances from account:", initGas - endGas);

    // estimate gas for grouping + getting balances
    initGas = gasleft();
    pcrm.getGroupedOptions(aliceAcc);
    console.log("gas: grouping 128 assets in PCRM:", initGas - gasleft());
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

    option = new Option();
    MockERC20 stable = new MockERC20("mock", "MOCK");
    cash = new CashAsset(IAccounts(account), IERC20Metadata(address(stable)));

    pcrm = new PCRM(
      address(account),
      address(spotFeeds),
      address(cash),
      address(option),
      address(auction)
    );

    pcrm.setParams(
      PCRM.Shocks({
        spotUpInitial: 120e16,
        spotDownInitial: 80e16,
        spotUpMaintenance: 110e16,
        spotDownMaintenance: 90e16,
        vol: 300e16,
        rfr: 10e16
      }),
      PCRM.Discounts({
        maintenanceStaticDiscount: 90e16, 
        initialStaticDiscount: 80e16
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
      assetTransfers[max_strikes + i] = AccountStructs.AssetTransfer({
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