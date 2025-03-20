// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "../../../risk-managers/unit-tests/PMRM_2_1/utils/PMRM_2_1SimTest.sol";

contract TestPMRM_2_1_PerpFeed is PMRM_2_1SimTest {
  function test_perpFeedAffectsPMRM_2_1() public {
    ISubAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".SinglePerp");
    _depositCash(aliceAcc, 10_000e18);
    _depositCash(bobAcc, 10_000e18);
    _doBalanceTransfer(aliceAcc, bobAcc, balances);

    IPMRM_2_1.Portfolio memory alicePort = pmrm_2_1.arrangePortfolio(aliceAcc);

    _logPortfolio(alicePort, 0);

    assertEq(alicePort.perpValue, 0);
    assertEq(alicePort.perpPosition, -1e18, "alice should be short 1 perp");
    int mmPre = pmrm_2_1.getMargin(aliceAcc, false);

    IPMRM_2_1.Portfolio memory bobPort = pmrm_2_1.arrangePortfolio(bobAcc);

    assertEq(bobPort.perpValue, 0);
    assertEq(bobPort.perpPosition, 1e18, "bob should be long 1 perp");

    // perp is trading 100 lower, so the unrealized PNL is +100 for alice
    mockPerp.setMockPerpPrice(1400e18, 1e18);
    mockPerp.mockAccountPnlAndFunding(aliceAcc, 0, 100e18);
    alicePort = pmrm_2_1.arrangePortfolio(aliceAcc);
    assertEq(alicePort.perpValue, 100e18);

    _logPortfolio(alicePort, 0);

    int mmPost = pmrm_2_1.getMargin(aliceAcc, false);
    // spot diff of 100 => spot shock is $15 worse (15%) for alice, so MM has increased by 15
    assertEq(mmPre - mmPost, -100e18 + -12e18);
  }
}
