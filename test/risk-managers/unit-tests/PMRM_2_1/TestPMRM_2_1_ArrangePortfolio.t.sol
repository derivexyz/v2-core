// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "../../../../src/risk-managers/PMRM_2_1.sol";
import {IAsset} from "../../../../src/interfaces/IAsset.sol";
import {ISubAccounts} from "../../../../src/interfaces/ISubAccounts.sol";
import "../../../shared/mocks/MockFeeds.sol";
import "../../../shared/mocks/MockFeeds.sol";
import "../../../risk-managers/unit-tests/PMRM_2_1/utils/PMRM_2_1TestBase.sol";

// TODO: catch edge cases in arrange
contract UNIT_TestPMRM_2_1_ArrangePortfolio is PMRM_2_1TestBase {
  ///////////////////////
  // Arrange Portfolio //
  ///////////////////////

  function testPMRM_2_1ArrangePortfolio_MaxExpiries() public {
    uint expiry = block.timestamp + 1000;
    ISubAccounts.AssetBalance[] memory balances = new ISubAccounts.AssetBalance[](pmrm_2_1.maxExpiries() + 1);
    for (uint i = 0; i < balances.length; i++) {
      balances[i] = ISubAccounts.AssetBalance({
        asset: IAsset(address(option)),
        subId: OptionEncoding.toSubId(expiry + i, 1500e18, true),
        balance: 1e18
      });
    }
    vm.expectRevert(IPMRM_2_1.PMRM_2_1_TooManyExpiries.selector);
    pmrm_2_1.arrangePortfolioByBalances(balances);
  }

  function testPMRM_2_1ArrangePortfolio_ExpiredOption() public {
    ISubAccounts.AssetBalance[] memory balances = new ISubAccounts.AssetBalance[](1);

    uint expiry = block.timestamp - 5;

    balances[0] = ISubAccounts.AssetBalance({
      asset: IAsset(address(option)),
      subId: OptionEncoding.toSubId(expiry, 1500e18, true),
      balance: 1e18
    });
    IPMRM_2_1.Portfolio memory portfolio = pmrm_2_1.arrangePortfolioByBalances(balances);

    assertEq(portfolio.expiries.length, 1);
    assertEq(portfolio.expiries[0].expiry, expiry);
    assertEq(portfolio.expiries[0].secToExpiry, 0);
  }
}
