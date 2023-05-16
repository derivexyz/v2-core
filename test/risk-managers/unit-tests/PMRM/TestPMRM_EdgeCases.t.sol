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

contract UNIT_TestPMRM_EdgeCases is PMRMTestBase {
  function testPMRM_perpTransfer() public {
    IAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".SinglePerp");

    _depositCash(aliceAcc, 2_000 ether);
    _depositCash(bobAcc, 2_000 ether);
    _doBalanceTransfer(aliceAcc, bobAcc, balances);

    _logPortfolio(pmrm.arrangePortfolio(aliceAcc));
  }

  function testPMRM_unsupportedAsset() public {
    MockAsset newAsset = new MockAsset(weth, accounts, true);

    IAccounts.AssetBalance[] memory balances = new IAccounts.AssetBalance[](1);
    balances[0] = IAccounts.AssetBalance({asset: IAsset(address(newAsset)), balance: 1_000 ether, subId: 0});
    vm.expectRevert(IPMRM.PMRM_UnsupportedAsset.selector);
    _doBalanceTransfer(aliceAcc, bobAcc, balances);
  }

  function testPMRM_merge() public {
    IAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".SinglePerp");

    _depositCash(aliceAcc, 2_000 ether);
    _depositCash(bobAcc, 2_000 ether);
    _doBalanceTransfer(aliceAcc, bobAcc, balances);

    vm.startPrank(alice);
    accounts.transferFrom(alice, bob, aliceAcc);
    vm.startPrank(bob);
    uint[] memory mergeAccs = new uint[](1);
    mergeAccs[0] = bobAcc;
    pmrm.mergeAccounts(aliceAcc, mergeAccs);

    IAccounts.AssetBalance[] memory bals = accounts.getAccountBalances(aliceAcc);
    assertEq(bals.length, 1);
    assertEq(bals[0].balance, 4_000 ether);
    assertEq(address(bals[0].asset), address(cash));
  }
}
