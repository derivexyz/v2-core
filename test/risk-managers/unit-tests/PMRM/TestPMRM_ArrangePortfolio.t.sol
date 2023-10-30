// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../../../src/risk-managers/PMRM.sol";
import {IAsset} from "../../../../src/interfaces/IAsset.sol";
import {ISubAccounts} from "../../../../src/interfaces/ISubAccounts.sol";
import "../../../shared/mocks/MockFeeds.sol";
import "../../../shared/mocks/MockFeeds.sol";
import "../../../risk-managers/unit-tests/PMRM/utils/PMRMTestBase.sol";

// TODO: catch edge cases in arrange
contract UNIT_TestPMRM_ArrangePortfolio is PMRMTestBase {
  ///////////////////////
  // Arrange Portfolio //
  ///////////////////////

  function testPMRMArrangePortfolio_MaxExpiries() public {
    uint expiry = block.timestamp + 1000;
    ISubAccounts.AssetBalance[] memory balances = new ISubAccounts.AssetBalance[](pmrm.maxExpiries() + 1);
    for (uint i = 0; i < balances.length; i++) {
      balances[i] = ISubAccounts.AssetBalance({
        asset: IAsset(address(option)),
        subId: OptionEncoding.toSubId(expiry + i, 1500e18, true),
        balance: 1e18
      });
    }
    vm.expectRevert(IPMRM.PMRM_TooManyExpiries.selector);
    pmrm.arrangePortfolioByBalances(balances);
  }

  function testPMRMArrangePortfolio_ExpiredOption() public {
    ISubAccounts.AssetBalance[] memory balances = new ISubAccounts.AssetBalance[](1);

    uint expiry = block.timestamp - 5;

    balances[0] = ISubAccounts.AssetBalance({
      asset: IAsset(address(option)),
      subId: OptionEncoding.toSubId(expiry, 1500e18, true),
      balance: 1e18
    });
    IPMRM.Portfolio memory portfolio = pmrm.arrangePortfolioByBalances(balances);

    assertEq(portfolio.expiries.length, 1);
    assertEq(portfolio.expiries[0].expiry, expiry);
    assertEq(portfolio.expiries[0].secToExpiry, 0);
  }
}
