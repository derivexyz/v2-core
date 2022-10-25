// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "src/Account.sol";
import "src/interfaces/IManager.sol";
import "src/interfaces/IAccount.sol";
import "src/interfaces/AccountStructs.sol";

import "forge-std/console2.sol";

import "../../account/mocks/assets/OptionToken.sol";
import "../../shared/mocks/MockAsset.sol";
import "../../account/mocks/assets/lending/Lending.sol";
import "../../account/mocks/assets/lending/ContinuousJumpRateModel.sol";
import "../../account/mocks/assets/lending/InterestRateModel.sol";
import "../../account/mocks/managers/PortfolioRiskPOCManager.sol";
import "../../shared/mocks/MockERC20.sol";
import "src/commitments/CommitmentAverage.sol";
import "./SimulationHelper.sol";


// run  with `forge script StallAttackScript --fork-url http://localhost:8545` against anvil
// OptionToken deployment fails when running outside of localhost

contract StallAttackScript is SimulationHelper {
  /* address setup */
  address node = vm.addr(2);
  address attacker = vm.addr(3);

  /**
   * @dev Simulation
   *  - 1x active node
   *  - 1x attacker node
   *  - 7x strikes and 8x expiries
   *  - 5min epochs
   *  - $500 deposit per subId
   */
  function run() external {
    console2.log("SETTING UP SIMULATION...");
    _deployAccountAndStables();
    _deployOptionAndManager();
    _deployCommitment();
    _setupParams(1500e18);
      
    /* mint dai and deposit to attacker account */
    console2.log("SETTING UP ATTACKER ACCOUNT...");
    vm.startBroadcast(owner);
    uint attackerAccId = account.createAccount(attacker, IManager(address(manager)));
    vm.stopBroadcast();
    _depositToAccount(attacker, attackerAccId, 1_000_000e18);

    /* deposit to node */
    _depositToNode(node, 100_000e18);
  }
}