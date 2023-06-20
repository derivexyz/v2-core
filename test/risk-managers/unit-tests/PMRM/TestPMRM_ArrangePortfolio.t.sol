pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "../../../../src/risk-managers/PMRM.sol";
import "../../../../src/assets/CashAsset.sol";
import "../../../../src/SubAccounts.sol";
import {IManager} from "../../../../src/interfaces/IManager.sol";
import {IAsset} from "../../../../src/interfaces/IAsset.sol";
import {ISubAccounts} from "../../../../src/interfaces/ISubAccounts.sol";

import "../../../shared/mocks/MockManager.sol";
import "../../../shared/mocks/MockERC20.sol";
import "../../../shared/mocks/MockAsset.sol";
import "../../../shared/mocks/MockOption.sol";
import "../../../shared/mocks/MockSM.sol";
import "../../../shared/mocks/MockFeeds.sol";

import "../../../risk-managers/mocks/MockDutchAuction.sol";
import "../../../shared/utils/JsonMechIO.sol";

import "../../../shared/mocks/MockFeeds.sol";
import "../../../../src/assets/WrappedERC20Asset.sol";
import "../../../shared/mocks/MockPerp.sol";

import "../../../risk-managers/unit-tests/PMRM/utils/PMRMTestBase.sol";

import "forge-std/console2.sol";

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

  function testPMRMArrangePortfolio_MaxAssets() public {
    uint expiry = block.timestamp + 1000;
    pmrm.setMaxAccountSize(10);
    ISubAccounts.AssetBalance[] memory balances = new ISubAccounts.AssetBalance[](pmrm.maxAccountSize() + 1);
    for (uint i = 0; i < balances.length; i++) {
      balances[i] = ISubAccounts.AssetBalance({
        asset: IAsset(address(option)),
        subId: OptionEncoding.toSubId(expiry, 1500e18 + i * 1e18, true),
        balance: 1e18
      });
    }
    vm.expectRevert(IPMRM.PMRM_TooManyAssets.selector);
    pmrm.arrangePortfolioByBalances(balances);
  }

  function testPMRMArrangePortfolio_ExpiredOption() public {
    uint buffer = pmrm.optionSettlementBuffer();

    ISubAccounts.AssetBalance[] memory balances = new ISubAccounts.AssetBalance[](1);
    balances[0] = ISubAccounts.AssetBalance({
      asset: IAsset(address(option)),
      subId: OptionEncoding.toSubId(block.timestamp - buffer - 1, 1500e18, true),
      balance: 1e18
    });
    vm.expectRevert(IPMRM.PMRM_OptionExpired.selector);
    pmrm.arrangePortfolioByBalances(balances);
  }

  function testPMRMArrangePortfolio_SlightlyExpiredOption() public {
    ISubAccounts.AssetBalance[] memory balances = new ISubAccounts.AssetBalance[](1);

    uint expiry = block.timestamp - 1;

    balances[0] = ISubAccounts.AssetBalance({
      asset: IAsset(address(option)),
      subId: OptionEncoding.toSubId(block.timestamp - 1, 1500e18, true),
      balance: 1e18
    });
    IPMRM.Portfolio memory portfolio = pmrm.arrangePortfolioByBalances(balances);

    assertEq(portfolio.expiries.length, 1);
    assertEq(portfolio.expiries[0].expiry, expiry);
    assertEq(portfolio.expiries[0].secToExpiry, 0);
  }
}
