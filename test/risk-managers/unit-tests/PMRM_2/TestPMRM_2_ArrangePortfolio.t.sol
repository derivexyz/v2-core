// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "../../../../src/risk-managers/PMRM_2.sol";
import {IAsset} from "../../../../src/interfaces/IAsset.sol";
import {ISubAccounts} from "../../../../src/interfaces/ISubAccounts.sol";
import "../../../shared/mocks/MockFeeds.sol";
import "../../../shared/mocks/MockFeeds.sol";
import "../../../risk-managers/unit-tests/PMRM_2/utils/PMRM_2TestBase.sol";

// TODO: catch edge cases in arrange
contract UNIT_TestPMRM_2_ArrangePortfolio is PMRM_2TestBase {
  ///////////////////////
  // Arrange Portfolio //
  ///////////////////////

  function testPMRM_2ArrangePortfolio_MaxExpiries() public {
    uint expiry = block.timestamp + 1000;
    ISubAccounts.AssetBalance[] memory balances = new ISubAccounts.AssetBalance[](pmrm_2.maxExpiries() + 1);
    for (uint i = 0; i < balances.length; i++) {
      balances[i] = ISubAccounts.AssetBalance({
        asset: IAsset(address(option)),
        subId: OptionEncoding.toSubId(expiry + i, 1500e18, true),
        balance: 1e18
      });
    }
    vm.expectRevert(IPMRM_2.PMRM_2_TooManyExpiries.selector);
    pmrm_2.arrangePortfolioByBalances(balances);
  }

  function testPMRM_2ArrangePortfolio_ExpiredOption() public {
    ISubAccounts.AssetBalance[] memory balances = new ISubAccounts.AssetBalance[](1);

    uint expiry = block.timestamp - 5;

    balances[0] = ISubAccounts.AssetBalance({
      asset: IAsset(address(option)),
      subId: OptionEncoding.toSubId(expiry, 1500e18, true),
      balance: 1e18
    });
    IPMRM_2.Portfolio memory portfolio = pmrm_2.arrangePortfolioByBalances(balances);

    assertEq(portfolio.expiries.length, 1);
    assertEq(portfolio.expiries[0].expiry, expiry);
    assertEq(portfolio.expiries[0].secToExpiry, 0);
  }
}
