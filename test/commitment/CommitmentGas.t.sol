// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "src/commitments/CommitmentBest.sol";
import "src/commitments/CommitmentAverage.sol";

contract CommitmentBestGas is Script {
  uint ownAcc;
  CommitmentBest commitment;

  uint expiry;

  function run() external {
    vm.startBroadcast();

    deployMockSystem();

    // gas tests
    uint gasBefore = gasleft();
    commitment.commit(100, 1, 1);
    uint gasAfter = gasleft();
    console.log("gas commit#1", gasBefore - gasAfter);

    gasBefore = gasleft();
    commitment.commit(100, 2, 1);
    gasAfter = gasleft();
    console.log("gas commit#2", gasBefore - gasAfter);

    _commitMultiple(100);
    vm.warp(block.timestamp + 10 minutes);

    gasBefore = gasleft();
    commitment.proccesQueue();
    gasAfter = gasleft();
    console.log("gas commit after process 100 in queue", gasBefore - gasAfter);

    vm.stopBroadcast();
  }

  function _commitMultiple(uint count) internal {
    for (uint i; i < count; i++) {
      commitment.commit(104, uint16(i), 1);
    }
  }

  function deployMockSystem() public {
    commitment = new CommitmentBest();
  }
}


contract CommitmentAvgGas is Script {
  uint ownAcc;
  CommitmentAverage commitment;

  uint expiry;

  function run() external {
    vm.startBroadcast();

    deployMockSystem();

    // gas tests
    uint gasBefore = gasleft();
    commitment.commit(100, 1, 1);
    uint gasAfter = gasleft();
    console.log("gas commit#1", gasBefore - gasAfter);

    gasBefore = gasleft();
    commitment.commit(102, 2, 1);
    gasAfter = gasleft();
    console.log("gas commit#2", gasBefore - gasAfter);

    gasBefore = gasleft();
    commitment.commit(104, 3, 1);
    gasAfter = gasleft();
    console.log("gas commit#3", gasBefore - gasAfter);

    vm.warp(block.timestamp + 5 minutes);

    gasBefore = gasleft();
    commitment.executeCommit(1, 1);
    gasAfter = gasleft();
    console.log("execute#1", gasBefore - gasAfter);
    
    gasBefore = gasleft();
    commitment.executeCommit(2, 1);
    gasAfter = gasleft();
    console.log("execute#2", gasBefore - gasAfter);

    // gasBefore = gasleft();
    // commitment.executeCommit(3, 1);
    // gasAfter = gasleft();
    // console.log("execute#3", gasBefore - gasAfter);

    vm.stopBroadcast();
  }

  function _commitMultiple(uint count) internal {
    for (uint i; i < count; i++) {
      commitment.commit(104, uint16(i), 1);
    }
  }

  function deployMockSystem() public {
    commitment = new CommitmentAverage();
  }
}
