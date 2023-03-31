pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "src/risk-managers/PMRM.sol";
import "src/assets/CashAsset.sol";
import "src/Accounts.sol";
import "src/interfaces/IManager.sol";
import "src/interfaces/IAsset.sol";
import "src/interfaces/AccountStructs.sol";

import "test/shared/mocks/MockManager.sol";
import "test/shared/mocks/MockERC20.sol";
import "test/shared/mocks/MockAsset.sol";
import "test/shared/mocks/MockOption.sol";
import "test/shared/mocks/MockSM.sol";
import "test/shared/mocks/MockFeed.sol";

import "test/risk-managers/mocks/MockDutchAuction.sol";
import "test/shared/utils/JsonMechIO.sol";

import "forge-std/console2.sol";

contract UNIT_TestPMRM is Test {
  using stdJson for string;

  Accounts accounts;
  PMRM pmrm;
  MockAsset cash;
  MockERC20 usdc;
  JsonMechIO jsonParser;

  MockOption option;
  MockDutchAuction auction;
  MockSM sm;
  MockFeed feed;
  uint feeRecipient;
  MTMCache mtmCache;

  address alice = address(0xaa);
  address bob = address(0xbb);
  uint aliceAcc;
  uint bobAcc;

  function setUp() public {
    accounts = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    usdc = new MockERC20("USDC", "USDC");
    option = new MockOption(accounts);
    cash = new MockAsset(usdc, accounts, true);
    mtmCache = new MTMCache();

    feed = new MockFeed();
    feed.setSpot(1500e18);

    pmrm = new PMRM(
      accounts,
      feed,
      feed,
      ICashAsset(address(cash)),
      option,
      feed,
      ISpotJumpOracle(address(0)),
      mtmCache
    );

    _setupAliceAndBob();
  }

  ///////////////////////
  // Arrange Portfolio //
  ///////////////////////

  function testPMRMTransaction() public {
    // same setup
    uint expiry = block.timestamp + 7 days;
    uint spot = feed.getFuturePrice(expiry);
    uint strike = spot + 1000e18;
    uint96 callToTrade = OptionEncoding.toSubId(expiry, strike, true);
    int amountOfContracts = 10e18;
    int premium = 1750e18;

    // open positions first
    _submitTrade(aliceAcc, option, callToTrade, amountOfContracts, bobAcc, cash, 0, premium);
  }

  function testPMRM() public {
    //    struct AssetBalance {
    //    IAsset asset;
    //    // adjustments will revert if > uint96
    //    uint subId;
    //    // base layer only stores up to int240
    //    int balance;
    //    }

    //    PMRM.NewPortfolio memory portfolio = pmrm.arrangePortfolio(getAssetBalancesForTestSmall());
    //    PMRM.NewPortfolio memory portfolio = pmrm.arrangePortfolio(getAssetBalancesForTestLarge());
    //    _logPortfolio(portfolio);
    addScenarios();

    pmrm.getIM(getAssetBalancesForTestLarge());
  }

  function getAssetBalancesForTestSmall() internal view returns (AccountStructs.AssetBalance[] memory balances) {
    uint referenceTime = block.timestamp;
    balances = new AccountStructs.AssetBalance[](4);
    balances[0] = AccountStructs.AssetBalance({asset: IAsset(cash), subId: 0, balance: -1000});
    balances[1] = AccountStructs.AssetBalance({
      asset: IAsset(option),
      subId: OptionEncoding.toSubId(referenceTime + 1 days, 1000e18, true),
      balance: -1000
    });
    balances[2] = AccountStructs.AssetBalance({
      asset: IAsset(option),
      subId: OptionEncoding.toSubId(referenceTime + 1 days, 1000e18, false),
      balance: -1000
    });

    balances[3] = AccountStructs.AssetBalance({
      asset: IAsset(option),
      subId: OptionEncoding.toSubId(referenceTime + 2 days, 1000e18, false),
      balance: -1000
    });
    return balances;
  }

  function getAssetBalancesForTestLarge() internal returns (AccountStructs.AssetBalance[] memory balances) {
    uint referenceTime = block.timestamp;
    jsonParser = new JsonMechIO();
    string memory json = jsonParser.jsonFromRelPath("/test/risk-managers/unit-tests/PMRM/testPortfolio.json");
    int[] memory data = json.readIntArray(".Test1");

    if (data.length % 4 != 0) {
      revert("Invalid data");
    }

    balances = new AccountStructs.AssetBalance[](data.length / 4 + 3);

    for (uint i = 0; i < data.length; i += 4) {
      balances[i / 4] = AccountStructs.AssetBalance({
        asset: IAsset(option),
        subId: OptionEncoding.toSubId(referenceTime + uint(data[i]) * 1 weeks, uint(data[i + 1] * 1e18), data[i + 2] == 1),
        balance: data[i + 3] * 1e18
      });
    }

    balances[balances.length - 3] = AccountStructs.AssetBalance({asset: IAsset(cash), subId: 0, balance: 200000 ether});
    balances[balances.length - 2] = AccountStructs.AssetBalance({
      // I.e. perps
      asset: IAsset(address(0xf00f00)),
      subId: 0,
      balance: -2000 ether
    });

    balances[balances.length - 1] = AccountStructs.AssetBalance({
      // I.e. wrapped eth
      asset: IAsset(address(0xbaabaa)),
      subId: 0,
      balance: 200 ether
    });
    return balances;
  }

  function _logPortfolio(PMRM.NewPortfolio memory portfolio) internal view {
    console2.log("cash balance:", portfolio.cash);
    console2.log("\nOTHER ASSETS");
    console2.log("count:", uint(portfolio.otherAssets.length));
    for (uint i = 0; i < portfolio.otherAssets.length; i++) {
      console2.log("- asset:", portfolio.otherAssets[i].asset);
      console2.log("- balance:", portfolio.otherAssets[i].amount);
      console2.log("----");
    }
    console2.log("\n");
    console2.log("expiryLen", uint(portfolio.expiries.length));
    for (uint i = 0; i < portfolio.expiries.length; i++) {
      PMRM.ExpiryHoldings memory expiry = portfolio.expiries[i];
      console2.log("==========");
      console2.log();
      console2.log("=== EXPIRY:", expiry.expiry);
      console2.log();
      console2.log("== CALLS:", expiry.calls.length);
      console2.log();
      for (uint i = 0; i < expiry.calls.length; i++) {
        console2.log("- strike:", expiry.calls[i].strike / 1e18);
        console2.log("- amount:", expiry.calls[i].amount / 1e18);
        console2.log();
      }
      console2.log("== PUTS:", expiry.puts.length);
      console2.log();
      for (uint i = 0; i < expiry.puts.length; i++) {
        console2.log("- strike:", expiry.puts[i].strike / 1e18);
        console2.log("- balance:", expiry.puts[i].amount / 1e18);
        console2.log();
      }
    }
  }

  function addScenarios() internal {
    // Scenario Number	Spot Shock (of max)	Vol Shock (of max)

    PMRM.Scenario[] memory scenarios = new PMRM.Scenario[](27);

    // add these 27 scenarios to the array
    scenarios[0] = PMRM.Scenario({spotShock: 1.2e18, volShock: 1.2e18});
    scenarios[1] = PMRM.Scenario({spotShock: 1.2e18, volShock: 1e18});
    scenarios[2] = PMRM.Scenario({spotShock: 1.2e18, volShock: 0.8e18});
    scenarios[3] = PMRM.Scenario({spotShock: 1.15e18, volShock: 1.2e18});
    scenarios[4] = PMRM.Scenario({spotShock: 1.15e18, volShock: 1e18});
    scenarios[5] = PMRM.Scenario({spotShock: 1.15e18, volShock: 0.8e18});
    scenarios[6] = PMRM.Scenario({spotShock: 1.1e18, volShock: 1.2e18});
    scenarios[7] = PMRM.Scenario({spotShock: 1.1e18, volShock: 1e18});
    scenarios[8] = PMRM.Scenario({spotShock: 1.1e18, volShock: 0.8e18});
    scenarios[9] = PMRM.Scenario({spotShock: 1.05e18, volShock: 1.2e18});
    scenarios[10] = PMRM.Scenario({spotShock: 1.05e18, volShock: 1e18});
    scenarios[11] = PMRM.Scenario({spotShock: 1.05e18, volShock: 0.8e18});
    scenarios[12] = PMRM.Scenario({spotShock: 1e18, volShock: 1.2e18});
    scenarios[13] = PMRM.Scenario({spotShock: 1e18, volShock: 1e18});
    scenarios[14] = PMRM.Scenario({spotShock: 1e18, volShock: 0.8e18});
    scenarios[15] = PMRM.Scenario({spotShock: 0.95e18, volShock: 1.2e18});
    scenarios[16] = PMRM.Scenario({spotShock: 0.95e18, volShock: 1e18});
    scenarios[17] = PMRM.Scenario({spotShock: 0.95e18, volShock: 0.8e18});
    scenarios[18] = PMRM.Scenario({spotShock: 0.9e18, volShock: 1.2e18});
    scenarios[19] = PMRM.Scenario({spotShock: 0.9e18, volShock: 1e18});
    scenarios[20] = PMRM.Scenario({spotShock: 0.9e18, volShock: 0.8e18});
    scenarios[21] = PMRM.Scenario({spotShock: 0.85e18, volShock: 1.2e18});
    scenarios[22] = PMRM.Scenario({spotShock: 0.85e18, volShock: 1e18});
    scenarios[23] = PMRM.Scenario({spotShock: 0.85e18, volShock: 0.8e18});
    scenarios[24] = PMRM.Scenario({spotShock: 0.8e18, volShock: 1.2e18});
    scenarios[25] = PMRM.Scenario({spotShock: 0.8e18, volShock: 1e18});
    scenarios[26] = PMRM.Scenario({spotShock: 0.8e18, volShock: 0.8e18});

    pmrm.setScenarios(scenarios);
  }

  function _submitTrade(
    uint accA,
    IAsset assetA,
    uint96 subIdA,
    int amountA,
    uint accB,
    IAsset assetB,
    uint subIdB,
    int amountB
  ) internal {
    AccountStructs.AssetTransfer[] memory transferBatch = new AccountStructs.AssetTransfer[](2);

    // accA transfer asset A to accB
    transferBatch[0] = AccountStructs.AssetTransfer({
      fromAcc: accA,
      toAcc: accB,
      asset: assetA,
      subId: subIdA,
      amount: amountA,
      assetData: bytes32(0)
    });

    // accB transfer asset B to accA
    transferBatch[1] = AccountStructs.AssetTransfer({
      fromAcc: accB,
      toAcc: accA,
      asset: assetB,
      subId: subIdB,
      amount: amountB,
      assetData: bytes32(0)
    });

    accounts.submitTransfers(transferBatch, "");
  }

  function _setupAliceAndBob() internal {
    vm.label(alice, "alice");
    vm.label(bob, "bob");

    aliceAcc = accounts.createAccount(alice, IManager(address(pmrm)));
    bobAcc = accounts.createAccount(bob, IManager(address(pmrm)));

    // allow this contract to submit trades
    vm.prank(alice);
    accounts.setApprovalForAll(address(this), true);
    vm.stopPrank();
    vm.prank(bob);
    accounts.setApprovalForAll(address(this), true);
    vm.stopPrank();

    usdc.mint(address(this), 1_000_000_000 ether);
    usdc.approve(address(cash), 1_000_000_000 ether);

    cash.deposit(aliceAcc, 200_000_000 ether);
    cash.deposit(bobAcc, 200_000_000 ether);
  }
}
