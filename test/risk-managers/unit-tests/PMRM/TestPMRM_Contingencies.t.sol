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
import "test/shared/mocks/MockFeeds.sol";

import "test/risk-managers/mocks/MockDutchAuction.sol";
import "test/shared/utils/JsonMechIO.sol";

import "test/shared/mocks/MockFeeds.sol";
import "src/assets/WrappedERC20Asset.sol";
import "test/shared/mocks/MockPerp.sol";

import "./PMRMTestBase.sol";

import "forge-std/console2.sol";

contract UNIT_TestPMRM_Contingencies is PMRMTestBase {
  // TODO: test all contingency calculations thoroughly
  ////////////////////////
  // Option Contingency //
  ////////////////////////

  function testPMRMScenario_OptionContingency() public {
    uint expiry = block.timestamp + 1000;
    IAccounts.AssetBalance[] memory balances = new IAccounts.AssetBalance[](2);
    balances[0] = IAccounts.AssetBalance({
      asset: IAsset(address(option)),
      subId: OptionEncoding.toSubId(block.timestamp + 1000, 1500e18, true),
      balance: -1e18
    });
    balances[1] = IAccounts.AssetBalance({
      asset: IAsset(address(option)),
      subId: OptionEncoding.toSubId(block.timestamp + 1000, 1500e18, false),
      balance: -1e18
    });

    IPMRM.Portfolio memory portfolio = pmrm.arrangePortfolioByBalances(balances);
    // contingency equals 2 short options worth
    assertEq(portfolio.staticContingency, 2 * 1500e18 * pmrm.getOtherContingencyParams().optionPercent / 1e18);
  }
}
