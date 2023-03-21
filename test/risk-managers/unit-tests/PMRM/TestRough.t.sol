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
import "test/shared/mocks/MockIPCRM.sol";
import "test/shared/mocks/MockFeed.sol";

import "test/risk-managers/mocks/MockDutchAuction.sol";
import "../../../shared/utils/JsonMechIO.sol";

contract UNIT_TestPMRM is Test {
  using stdJson for string;

  Accounts account;
  PMRM pmrm;
  MockIPCRM pcrm;
  MockAsset cash;
  MockERC20 usdc;
  JsonMechIO jsonParser;

  MockOption option;
  MockDutchAuction auction;
  MockSM sm;
  MockFeed feed;
  uint feeRecipient;

  address alice = address(0xaa);
  address bob = address(0xbb);
  uint aliceAcc;
  uint bobAcc;

  function setUp() public {
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    usdc = new MockERC20("USDC", "USDC");
    option = new MockOption(account);
    cash = new MockAsset(usdc, account, true);

    feed = new MockFeed();

    pmrm = new PMRM(
      account,
      feed,
      feed,
      ICashAsset(address(cash)),
      option,
      ISpotJumpOracle(address(0))
    );
  }

  ///////////////////////
  // Arrange Portfolio //
  ///////////////////////

  function testPMRM() public {
    //    struct AssetBalance {
    //    IAsset asset;
    //    // adjustments will revert if > uint96
    //    uint subId;
    //    // base layer only stores up to int240
    //    int balance;
    //    }

    //    PMRM.NewPortfolio memory portfolio = pmrm.arrangePortfolio(getAssetBalancesForTestSmall());
    PMRM.NewPortfolio memory portfolio = pmrm.arrangePortfolio(getAssetBalancesForTestLarge());
    _logPortfolio(portfolio);
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
    jsonParser = new JsonMechIO();
    string memory json = jsonParser.jsonFromRelPath("/test/risk-managers/unit-tests/PMRM/testPortfolio.json");
    int[] memory data = json.readIntArray(".Test1");

    if (data.length % 4 != 0) {
      revert("Invalid data");
    }

    balances = new AccountStructs.AssetBalance[](data.length / 4 + 3);

    uint offset = 0;
    for (uint i = 0; i < data.length; i += 4) {
      if (data[i + 3] == 0) {
        offset++;
        continue;
      }
      balances[i / 4 - offset] = AccountStructs.AssetBalance({
        asset: IAsset(option),
        subId: OptionEncoding.toSubId(
          uint(data[i]), uint(data[i + 1] * 1e18), data[i + 2] == 1
          ),
        balance: data[i + 3] * 1e18
      });
    }

    balances[balances.length - 3 - offset] = AccountStructs.AssetBalance({
      asset: IAsset(cash),
      subId: 0,
      balance: 200000 ether
    });
    balances[balances.length - 2 - offset] = AccountStructs.AssetBalance({
      // I.e. perps
      asset: IAsset(address(0xf00f00)),
      subId: 0,
      balance: -200000 ether
    });

    balances[balances.length - 1 - offset] = AccountStructs.AssetBalance({
      // I.e. wrapped eth
      asset: IAsset(address(0xbaabaa)),
      subId: 0,
      balance: 200000 ether
    });
    return balances;
  }

  function _logPortfolio(PMRM.NewPortfolio memory portfolio) internal view {

    console2.log("cash balance:", portfolio.cash);
    console2.log("\nOTHER ASSETS");
    console2.log("count:", uint(portfolio.otherAssets.length));
    for (uint i=0; i<portfolio.otherAssets.length; i++) {
      console2.log("- asset:", portfolio.otherAssets[i].asset);
      console2.log("- balance:", portfolio.otherAssets[i].amount);
      console2.log("----");
    }
    console2.log("\n");
    console2.log("expiryLen", uint(portfolio.expiries.length));
    for (uint i=0; i<portfolio.expiries.length; i++) {
      PMRM.ExpiryHoldings memory expiry = portfolio.expiries[i];
      console2.log("==========");
      console2.log();
      console2.log("=== EXPIRY:", expiry.expiry);
      console2.log();
      console2.log("== CALLS:", expiry.calls.length);
      console2.log();
      for (uint i=0; i<expiry.calls.length; i++) {
        console2.log("- strike:", expiry.calls[i].strike / 1e18);
        console2.log("- amount:", expiry.calls[i].amount / 1e18);
        console2.log();
      }
      console2.log("== CALL SPREADS:", expiry.callSpreads.length);
      console2.log();
      for (uint i=0; i<expiry.callSpreads.length; i++) {
        console2.log("- strikeLower:", expiry.callSpreads[i].strikeLower / 1e18);
        console2.log("- strikeUpper:", expiry.callSpreads[i].strikeUpper / 1e18);
        console2.log("- amount:", expiry.callSpreads[i].amount / 1e18);
        console2.log();
      }
      console2.log("== PUTS:", expiry.puts.length);
      console2.log();
      for (uint i=0; i<expiry.puts.length; i++) {
        console2.log("- strike:", expiry.puts[i].strike / 1e18);
        console2.log("- balance:", expiry.puts[i].amount / 1e18);
        console2.log();
      }
      console2.log("== PUT SPREADS:", expiry.putSpreads.length);
      console2.log();
      for (uint i=0; i<expiry.putSpreads.length; i++) {
        console2.log("- strikeLower:", expiry.putSpreads[i].strikeLower / 1e18);
        console2.log("- strikeUpper:", expiry.putSpreads[i].strikeUpper / 1e18);
        console2.log("- amount:", expiry.putSpreads[i].amount / 1e18);
        console2.log();
      }
    }
  }
}
