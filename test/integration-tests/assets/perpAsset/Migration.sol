// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import "lyra-utils/encoding/OptionEncoding.sol";
import "../../shared/IntegrationTestBase.t.sol";

/**
 * This test use the real SRM / PMRM / settlement after perp is disabled
 */
contract INTEGRATION_PerpMigration is IntegrationTestBase {
  address charlie = address(0xca1e);
  address daniel = address(0xda1e);
  uint charlieAcc;
  uint danielAcc;

  uint initPrice = 1500e18;

  function setUp() public {
    // deploy contracts
    _setupIntegrationTestComplete();

    // init setup for both accounts
    charlieAcc = subAccounts.createAccountWithApproval(charlie, address(this), markets["weth"].pmrm);
    danielAcc = subAccounts.createAccountWithApproval(daniel, address(this), markets["weth"].pmrm);

    _depositCash(alice, aliceAcc, DEFAULT_DEPOSIT);
    _depositCash(bob, charlieAcc, DEFAULT_DEPOSIT);
    _depositCash(daniel, danielAcc, DEFAULT_DEPOSIT);

    _setSpotPrice("weth", 2000e18, 1e18);
    _setPerpPrice("weth", 2000e18, 1e18);

    // open trades: Alice is Short, Bob is Long
    _tradePerpContract(markets["weth"].perp, aliceAcc, charlieAcc, 1e18);

    // increase price to have something to settle
    _setPerpPrice("weth", 2200e18, 1e18);

    // disable market
    markets["weth"].perp.disable();

    // asset beginning with 1e18 balances
    assertEq(subAccounts.getBalance(aliceAcc, markets["weth"].perp, 0), -1e18);
    assertEq(subAccounts.getBalance(bobAcc, markets["weth"].perp, 0), 0);
    assertEq(subAccounts.getBalance(charlieAcc, markets["weth"].perp, 0), 1e18);
    assertEq(subAccounts.getBalance(danielAcc, markets["weth"].perp, 0), 0);

  }

  function testCannotOpenNewTrade() public {
    // trade should revert
    vm.expectRevert(bytes("ReentrancyGuard: reentrant call"));
    _tradePerpContract(markets["weth"].perp, danielAcc, bobAcc, 1e18);

    // daniel and bob balances should not have changed
    assertEq(subAccounts.getBalance(danielAcc, markets["weth"].perp, 0), 0);
    assertEq(subAccounts.getBalance(bobAcc, markets["weth"].perp, 0), 0);
  }

  function testCannotTradeAfterDisabled() public {
    // trade should revert
    vm.expectRevert(bytes("ReentrancyGuard: reentrant call"));
    _tradePerpContract(markets["weth"].perp, charlieAcc, aliceAcc, 2e18);

    // alice and charlie balances should not have changed
    assertEq(subAccounts.getBalance(aliceAcc, markets["weth"].perp, 0), -1e18);
    assertEq(subAccounts.getBalance(charlieAcc, markets["weth"].perp, 0), 1e18);

    // no settlements should have happened
    assertEq(_getCashBalance(aliceAcc), int(DEFAULT_DEPOSIT));
    assertEq(_getCashBalance(charlieAcc), int(DEFAULT_DEPOSIT));
  }

  function testCanSettleOpenBalance() public {
    // close out and settle all perps
    vm.prank(address(srm));
    srm.settlePerpsWithIndex(aliceAcc);
    vm.prank(address(markets["weth"].pmrm));
    markets["weth"].pmrm.settlePerpsWithIndex(charlieAcc);

    // alice and charlie should both have 0 balances
    assertEq(subAccounts.getBalance(aliceAcc, markets["weth"].perp, 0), 0);
    assertEq(subAccounts.getBalance(charlieAcc, markets["weth"].perp, 0), 0);

    // confirm correct settlement
    assertEq(int(DEFAULT_DEPOSIT) - 200e18, _getCashBalance(aliceAcc));
    assertEq(int(DEFAULT_DEPOSIT) + 200e18, _getCashBalance(charlieAcc));
  }

  function testTradeIfClosingOutBalance() public {
    // trade should revert
    _tradePerpContract(markets["weth"].perp, charlieAcc, aliceAcc, 1e18);

    // alice and charlie should both have 0 balances
    assertEq(subAccounts.getBalance(aliceAcc, markets["weth"].perp, 0), 0);
    assertEq(subAccounts.getBalance(charlieAcc, markets["weth"].perp, 0), 0);

    // confirm alice settled properly
    assertEq(int(DEFAULT_DEPOSIT) - 200e18, _getCashBalance(aliceAcc));
    assertEq(int(DEFAULT_DEPOSIT) + 200e18, _getCashBalance(charlieAcc));
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
