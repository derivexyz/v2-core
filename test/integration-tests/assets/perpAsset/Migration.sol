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
  uint charlieAcc;
  
  uint initPrice = 1500e18;

  function setUp() public {
    // deploy contracts
    _setupIntegrationTestComplete();

    // init setup for both accounts
    charlieAcc = subAccounts.createAccountWithApproval(charlie, address(this), markets["weth"].pmrm);
    _depositCash(alice, aliceAcc, DEFAULT_DEPOSIT);
    _depositCash(bob, charlieAcc, DEFAULT_DEPOSIT);

    _setSpotPrice("weth", 2000e18, 1e18);
    _setPerpPrice("weth", 2000e18, 1e18);

    // open trades: Alice is Short, Bob is Long
    _tradePerpContract(markets["weth"].perp, aliceAcc, charlieAcc, 1e18);
    markets["weth"].perp.disable();

    // asset beginning with 1e18 balances
    assertEq(subAccounts.getBalance(aliceAcc, markets["weth"].perp, 0), -1e18);
    assertEq(subAccounts.getBalance(bobAcc, markets["weth"].perp, 0), 0);
    assertEq(subAccounts.getBalance(charlieAcc, markets["weth"].perp, 0), 1e18);
  }

  function testTradeIfClosingOutBalance() public {
    _setPerpPrice("weth", 2500e18, 1e18);

    // trade should revert
    _tradePerpContract(markets["weth"].perp, charlieAcc, aliceAcc, 1e18);

    // alice and charlie should both have 0 balances
    assertEq(subAccounts.getBalance(aliceAcc, markets["weth"].perp, 0), 0);
    assertEq(subAccounts.getBalance(charlieAcc, markets["weth"].perp, 0), 0);
  }

  function testCannotTradeAfterDisabled() public {
    _setPerpPrice("weth", 2500e18, 1e18);

    // trade should revert
    vm.expectRevert(bytes("ReentrancyGuard: reentrant call"));
    _tradePerpContract(markets["weth"].perp, charlieAcc, aliceAcc, 2e18);

    // alice and charlie balances should not have changed
    assertEq(subAccounts.getBalance(aliceAcc, markets["weth"].perp, 0), -1e18);
    assertEq(subAccounts.getBalance(charlieAcc, markets["weth"].perp, 0), 1e18);
  }

  function testCanSettleOpenBalance() public {

    _setPerpPrice("weth", 2500e18, 1e18);

    // close out and settle all perps
    vm.prank(address(srm));
    srm.settlePerpsWithIndex(aliceAcc);
    vm.prank(address(markets["weth"].pmrm));
    markets["weth"].pmrm.settlePerpsWithIndex(charlieAcc);

    // alice and charlie should both have 0 balances
    assertEq(subAccounts.getBalance(aliceAcc, markets["weth"].perp, 0), 0);
    assertEq(subAccounts.getBalance(charlieAcc, markets["weth"].perp, 0), 0);
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
