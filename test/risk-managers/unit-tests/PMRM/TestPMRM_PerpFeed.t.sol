pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "./PMRMTestBase.sol";

import "forge-std/console2.sol";

contract TestPMRM_PerpFeed is PMRMTestBase {
  function test_perpFeedAffectsPMRM() public {
    IAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".SinglePerp");
    _depositCash(aliceAcc, 1_000_000e18);
    _depositCash(bobAcc, 1_000_000e18);
    _doBalanceTransfer(aliceAcc, bobAcc, balances);

    IPMRM.Portfolio memory alicePort = pmrm.arrangePortfolio(aliceAcc);

    assertEq(alicePort.perpValue, 0);
    assertEq(alicePort.perpPosition, -1e18, "alice should be short 1 perp");
    int mmPre = pmrm.getMargin(aliceAcc, false);

    IPMRM.Portfolio memory bobPort = pmrm.arrangePortfolio(bobAcc);

    assertEq(bobPort.perpValue, 0);
    assertEq(bobPort.perpPosition, 1e18, "bob should be long 1 perp");

    // perp is trading 100 lower
    perpFeed.setSpot(1400e18, 1e18);
    mockPerp.mockAccountPnlAndFunding(aliceAcc, 0, -100e18);

    alicePort = pmrm.arrangePortfolio(aliceAcc);
    assertEq(alicePort.perpValue, -100e18);

    int mmPost = pmrm.getMargin(aliceAcc, false);
    // spot diff of 100 => spot shock is $15 worse (15%) for alice, so MM has increased by 15
    assertEq(mmPre - mmPost, -15e18);
  }
}
