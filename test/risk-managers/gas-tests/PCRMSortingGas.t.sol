pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "test/feeds/mocks/MockV3Aggregator.sol";
import "src/feeds/ChainlinkSpotFeeds.sol";
import "src/assets/Option.sol";
import "src/risk-managers/PCRM.sol";
import "src/Account.sol";
import "src/interfaces/IManager.sol";
import "src/interfaces/IAsset.sol";
import "src/interfaces/AccountStructs.sol";
import "test/shared/mocks/MockManager.sol";
import "test/risk-managers/mocks/MockDutchAuction.sol";

contract PCRMSortingGas is Script {
  Account account;
  PCRM pcrm;

  ChainlinkSpotFeeds spotFeeds;
  MockV3Aggregator aggregator;
  Option option;
  MockDutchAuction auction;

  address alice = address(0xaa);
  address bob = address(0xbb);
  uint aliceAcc;
  uint bobAcc;

  function run() external {
    vm.startBroadcast(alice);

    _setup();

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

    // estimate tx cost
    uint initGas = gasleft();
    account.submitTransfer(transfer, "");
    uint endGas = gasleft();

    console.log("gas:singleAsset:", initGas - endGas);
  }

  function _gasMaxAssets() public {
    AccountStructs.AssetTransfer[] memory assetTransfers = _composeMaxTransfers();

    // create account
    for (uint i; i < assetTransfers.length; i++) {
      account.submitTransfer(assetTransfers[i], "");
    }

    // estimate gas for only sorting
    uint initGas = gasleft();
    pcrm.getSortedHoldings(aliceAcc);
    uint endGas = gasleft();

    console.log("gas: 128 assets in PCRM:", initGas - endGas);
  }

  function _setup() public {
    account = new Account("Lyra Margin Accounts", "LyraMarginNFTs");

    aggregator = new MockV3Aggregator(18, 1000e18);
    spotFeeds = new ChainlinkSpotFeeds();
    spotFeeds.addFeed("ETH/USD", address(aggregator), 1 hours);

    auction = new MockDutchAuction();

    option = new Option();
    pcrm = new PCRM(
      address(account),
      address(spotFeeds),
      address(0), // lending
      address(option),
      address(auction)
    );
  }

  function _composeMaxTransfers() public view returns (AccountStructs.AssetTransfer[] memory assetTransfers) {
    //
    uint max_strikes = pcrm.MAX_STRIKES();
    uint max_expiries = pcrm.MAX_EXPIRIES();

    uint max_unique_options = max_strikes * max_expiries;
    assetTransfers = new AccountStructs.AssetTransfer[](max_unique_options);

    //
    uint baseExpiry = block.timestamp;
    uint baseStrike = 0;
    for (uint i; i < max_expiries; i++) {
      for (uint j; j < max_strikes; j++) {
        uint newSubId = OptionEncoding.toSubId(baseExpiry + i, baseStrike + j * 10e18, true);
        assetTransfers[i * max_strikes + j] = AccountStructs.AssetTransfer({
          fromAcc: aliceAcc,
          toAcc: bobAcc,
          asset: IAsset(option),
          subId: newSubId,
          amount: 1e18,
          assetData: ""
        });
      }
    }

    return assetTransfers;
  }
}
