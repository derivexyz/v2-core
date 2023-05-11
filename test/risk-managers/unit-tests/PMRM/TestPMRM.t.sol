pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "src/risk-managers/PMRM.sol";
import "src/assets/CashAsset.sol";
import "src/Accounts.sol";
import "src/interfaces/IManager.sol";
import "src/interfaces/IAsset.sol";
import "src/interfaces/IAccounts.sol";

import "test/shared/mocks/MockManager.sol";
import "test/shared/mocks/MockERC20.sol";
import "test/shared/mocks/MockAsset.sol";
import "test/shared/mocks/MockOption.sol";
import "test/shared/mocks/MockSM.sol";
import "test/shared/mocks/MockFeed.sol";

import "test/risk-managers/mocks/MockDutchAuction.sol";
import "test/shared/utils/JsonMechIO.sol";

import "test/shared/mocks/MockFeeds.sol";
import "src/assets/WrappedERC20Asset.sol";
import "test/shared/mocks/MockPerp.sol";

import "./PMRMTestBase.sol";

import "forge-std/console2.sol";

contract UNIT_TestPMRM is PMRMTestBase {
  ///////////////////////
  // Arrange Portfolio //
  ///////////////////////

  //  function testPMRMTransaction() public {
  //    // same setup
  //    uint expiry = block.timestamp + 7 days;
  //    uint spot = _getForwardPrice(expiry);
  //    uint strike = spot + 1000e18;
  //    uint96 callToTrade = OptionEncoding.toSubId(expiry, strike, true);
  //    int amountOfContracts = 10e18;
  //    int premium = 1750e18;
  //
  //    // open positions first
  //    _submitTrade(aliceAcc, option, callToTrade, amountOfContracts, bobAcc, cash, 0, premium);
  //  }

  function testPMRM() public {
    //    struct AssetBalance {
    //    IAsset asset;
    //    // adjustments will revert if > uint96
    //    uint subId;
    //    // base layer only stores up to int240
    //    int balance;
    //    }

    //    PMRM.NewPortfolio memory portfolio = pmrm.arrangePortfolio(getAssetBalancesForTestSmall());

    //
    //    IAccounts.AssetBalance[] memory balances = getAssetBalancesForTestLarge();
    //
    //    console.log(balances.length);
    IAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".T8");
    IPMRM.PMRM_Portfolio memory portfolio = pmrm.arrangePortfolio(balances);
    _logPortfolio(portfolio);
    console2.log("im", pmrm.getMargin(balances, true));
    console2.log("mm", pmrm.getMargin(balances, false));
  }
  //
  //  function getAssetBalancesForTestSmall() internal view returns (IAccounts.AssetBalance[] memory balances) {
  //    uint referenceTime = block.timestamp;
  //    balances = new IAccounts.AssetBalance[](4);
  //    balances[0] = IAccounts.AssetBalance({asset: IAsset(cash), subId: 0, balance: -1000});
  //    balances[1] = IAccounts.AssetBalance({
  //      asset: IAsset(option),
  //      subId: OptionEncoding.toSubId(referenceTime + 1 days, 1000e18, true),
  //      balance: -1000
  //    });
  //    balances[2] = IAccounts.AssetBalance({
  //      asset: IAsset(option),
  //      subId: OptionEncoding.toSubId(referenceTime + 1 days, 1000e18, false),
  //      balance: -1000
  //    });
  //
  //    balances[3] = IAccounts.AssetBalance({
  //      asset: IAsset(option),
  //      subId: OptionEncoding.toSubId(referenceTime + 2 days, 1000e18, false),
  //      balance: -1000
  //    });
  //    return balances;
  //  }
}
