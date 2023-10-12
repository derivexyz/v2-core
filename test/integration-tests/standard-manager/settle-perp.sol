// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import "lyra-utils/encoding/OptionEncoding.sol";
import "../shared/IntegrationTestBase.t.sol";

/**
 * This test use the real StandardManager & PerpAsset to test the settlement flow
 */
contract INTEGRATION_SRM_PerpSettlement is IntegrationTestBase {
  int oneContract = 1e18;

  uint initPrice = 1500e18;

  function setUp() public {
    // deploy contracts
    _setupIntegrationTestComplete();

    // init setup for both accounts
    _depositCash(alice, aliceAcc, DEFAULT_DEPOSIT);
    _depositCash(bob, bobAcc, DEFAULT_DEPOSIT);

    _setPerpPrice("weth", 1500e18, 1e18);

    // open trades: Alice is Short, Bob is Long
    _tradePerpContract(markets["weth"].perp, aliceAcc, bobAcc, oneContract);
  }

  function testSettleLongPosition() public {
    int cashBefore = _getCashBalance(bobAcc);

    _setPerpPrice("weth", 1600e18, 1e18);

    // bobAcc close his position and has $100 in PNL
    _tradePerpContract(markets["weth"].perp, bobAcc, aliceAcc, oneContract);

    int cashAfter = _getCashBalance(bobAcc);

    // bob has $100 in PNL
    assertEq(cashBefore + 100e18, cashAfter);
  }

  function testSettleShortPosition() public {
    int cashBefore = _getCashBalance(aliceAcc);

    // alice is short, bob is long
    _setPerpPrice("weth", 1600e18, 1e18);

    // alice close his position and has $100 in PNL
    _tradePerpContract(markets["weth"].perp, bobAcc, aliceAcc, oneContract);

    int cashAfter = _getCashBalance(aliceAcc);

    // alice has lost $100
    assertEq(cashBefore - 100e18, cashAfter);
  }

  function testCanSettleUnrealizedLossForAnyAccount() public {
    int cashBefore = _getCashBalance(aliceAcc);

    // alice is short, bob is long
    _setPerpPrice("weth", 1600e18, 1e18);

    srm.settlePerpsWithIndex(aliceAcc);

    int cashAfter = _getCashBalance(aliceAcc);
    assertEq(cashBefore - 100e18, cashAfter);
  }

  function testCanSettleUnrealizedPNLForAnyAccount() public {
    int aliceCashBefore = _getCashBalance(aliceAcc);
    int bobCashBefore = _getCashBalance(bobAcc);

    // alice is short, bob is long
    _setPerpPrice("weth", 1600e18, 1e18);

    srm.settlePerpsWithIndex(aliceAcc);
    srm.settlePerpsWithIndex(bobAcc);

    int aliceCashAfter = _getCashBalance(aliceAcc);
    int bobCashAfter = _getCashBalance(bobAcc);

    // alice loss $100
    assertEq(aliceCashBefore - 100e18, aliceCashAfter);

    // bob gets $100
    assertEq(bobCashBefore + 100e18, bobCashAfter);
  }

  function testCanSettleIntoNegativeCash() public {
    _setPerpPrice("weth", 200_000e18, 1e18);
    srm.settlePerpsWithIndex(aliceAcc);
    assertLt(_getCashBalance(aliceAcc), 0);
  }

  function _getEntryPriceAndPNL(uint acc) internal view returns (uint, int) {
    (uint entryPrice,, int pnl,,) = markets["weth"].perp.positions(acc);
    return (entryPrice, pnl);
  }

  function _tradePerpContract(IPerpAsset perp, uint fromAcc, uint toAcc, int amount) internal {
    ISubAccounts.AssetTransfer memory transfer =
      ISubAccounts.AssetTransfer({fromAcc: fromAcc, toAcc: toAcc, asset: perp, subId: 0, amount: amount, assetData: ""});
    subAccounts.submitTransfer(transfer, "");
  }

  function _getCashBalance(uint acc) public view returns (int) {
    return subAccounts.getBalance(acc, cash, 0);
  }
}
