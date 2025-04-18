// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "../../../../src/risk-managers/PMRM_2.sol";
import {IAsset} from "../../../../src/interfaces/IAsset.sol";
import {ISubAccounts} from "../../../../src/interfaces/ISubAccounts.sol";
import "../../../risk-managers/unit-tests/PMRM_2/utils/PMRM_2TestBase.sol";

contract UNIT_TestPMRM_2_Contingencies is PMRM_2TestBase {
  // TODO: test all contingency calculations thoroughly
  ////////////////////////
  // Option Contingency //
  ////////////////////////

  function testPMRM_2Scenario_OptionContingency() public {
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

    IPMRM_2.Portfolio memory portfolio = pmrm_2.arrangePortfolioByBalances(balances);
    // contingency equals 2 short options worth
    // TODO
    //    assertEq(portfolio.staticContingency, 2 * 1500e18 * lib.getOtherContingencyParams().optionPercent / 1e18);
  }
}
