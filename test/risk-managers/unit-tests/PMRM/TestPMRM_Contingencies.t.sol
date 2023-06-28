pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "src/risk-managers/PMRM.sol";
import {IAsset} from "src/interfaces/IAsset.sol";
import {ISubAccounts} from "src/interfaces/ISubAccounts.sol";

import "test/shared/mocks/MockFeeds.sol";

import "test/shared/mocks/MockFeeds.sol";

import "test/risk-managers/unit-tests/PMRM/utils/PMRMTestBase.sol";

contract UNIT_TestPMRM_Contingencies is PMRMTestBase {
  // TODO: test all contingency calculations thoroughly
  ////////////////////////
  // Option Contingency //
  ////////////////////////

  function testPMRMScenario_OptionContingency() public {
    uint expiry = block.timestamp + 1000;
    ISubAccounts.AssetBalance[] memory balances = new ISubAccounts.AssetBalance[](2);
    balances[0] = ISubAccounts.AssetBalance({
      asset: IAsset(address(option)),
      subId: OptionEncoding.toSubId(expiry, 1500e18, true),
      balance: -1e18
    });
    balances[1] = ISubAccounts.AssetBalance({
      asset: IAsset(address(option)),
      subId: OptionEncoding.toSubId(expiry, 1500e18, false),
      balance: -1e18
    });

    IPMRM.Portfolio memory portfolio = pmrm.arrangePortfolioByBalances(balances);
    // contingency equals 2 short options worth
    assertEq(portfolio.staticContingency, 2 * 1500e18 * lib.getOtherContingencyParams().optionPercent / 1e18);
  }
}
