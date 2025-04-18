// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "../../../risk-managers/unit-tests/PMRM/utils/PMRMSimTest.sol";

contract TestPMRM_PerpFeed is PMRMSimTest {
  function test_perpFeedAffectsPMRM() public {
    ISubAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".SinglePerp");
    _depositCash(aliceAcc, 10_000e18);
    _depositCash(bobAcc, 10_000e18);
    _doBalanceTransfer(aliceAcc, bobAcc, balances);

    IPMRM.Portfolio memory alicePort = pmrm.arrangePortfolio(aliceAcc);

    _logPortfolio(alicePort);

    assertEq(alicePort.perpValue, 0);
    assertEq(alicePort.perpPosition, -1e18, "alice should be short 1 perp");
    int mmPre = pmrm.getMargin(aliceAcc, false);

    IPMRM.Portfolio memory bobPort = pmrm.arrangePortfolio(bobAcc);

    assertEq(bobPort.perpValue, 0);
    assertEq(bobPort.perpPosition, 1e18, "bob should be long 1 perp");

    // perp is trading 100 lower, so the unrealized PNL is +100 for alice
    mockPerp.setMockPerpPrice(1400e18, 1e18);
    mockPerp.mockAccountPnlAndFunding(aliceAcc, 0, 100e18);
    alicePort = pmrm.arrangePortfolio(aliceAcc);
    assertEq(alicePort.perpValue, 100e18);

    _logPortfolio(alicePort);

    int mmPost = pmrm.getMargin(aliceAcc, false);
    // spot diff of 100 => spot shock is $15 worse (15%) for alice, so MM has increased by 15
    assertEq(mmPre - mmPost, -100e18 + -15e18);
  }
}
