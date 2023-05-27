pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "src/risk-managers/PMRM.sol";
import "src/assets/CashAsset.sol";
import "src/SubAccounts.sol";
import "src/interfaces/IManager.sol";
import "src/interfaces/IAsset.sol";
import "src/interfaces/ISubAccounts.sol";

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

// TODO: catch edge cases in arrange
contract UNIT_TestPMRM_ArrangePortfolio is PMRMTestBase {
  ///////////////////////
  // Arrange Portfolio //
  ///////////////////////

  function testPMRMArrangePortfolio_MaxExpiries() public {
    uint expiry = block.timestamp + 1000;
    ISubAccounts.AssetBalance[] memory balances = new ISubAccounts.AssetBalance[](pmrm.MAX_EXPIRIES() + 1);
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
    ISubAccounts.AssetBalance[] memory balances = new ISubAccounts.AssetBalance[](pmrm.MAX_ASSETS() + 1);
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
    ISubAccounts.AssetBalance[] memory balances = new ISubAccounts.AssetBalance[](1);
    balances[0] = ISubAccounts.AssetBalance({
      asset: IAsset(address(option)),
      subId: OptionEncoding.toSubId(block.timestamp - 1, 1500e18, true),
      balance: 1e18
    });
    vm.expectRevert(IPMRM.PMRM_OptionExpired.selector);
    pmrm.arrangePortfolioByBalances(balances);
  }
}
