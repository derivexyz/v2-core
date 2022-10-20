// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "src/commitments/CommitmentBest.sol";

contract UNIT_CommitBest is Test {
  CommitmentBest commitment;
  uint16 constant commitmentWeight = 1;

  constructor() {
    commitment = new CommitmentBest();

    vm.warp(block.timestamp + 1 days);
  }

  function testCanCommit() public {
    commitment.commit(100, 1, commitmentWeight);
    commitment.commit(100, 2, commitmentWeight);
    commitment.commit(102, 3, commitmentWeight);
    commitment.commit(105, 4, commitmentWeight);

    vm.warp(block.timestamp + 10 minutes);

    commitment.checkRollover();

    assertEq(commitment.pendingLength(), 4);
    assertEq(commitment.collectingLength(), 0);
  }

  function testCanExecuteCommit() public {
    commitment.commit(100, 1, commitmentWeight); // collecting: 1, pending: 0
    commitment.commit(104, 2, commitmentWeight); // collecting: 2, pending: 0
    commitment.commit(102, 3, commitmentWeight); // collecting: 3, pending: 0
    assertEq(commitment.collectingLength(), 3);

    vm.warp(block.timestamp + 10 minutes);
    commitment.checkRollover();

    assertEq(commitment.pendingLength(), 3);

    commitment.executeCommit(0, commitmentWeight);
    commitment.executeCommit(1, commitmentWeight);

    vm.warp(block.timestamp + 10 minutes);
    commitment.checkRollover();

    (uint16 bestVol, uint16 nodeId, uint16 commitments, uint64 bidTimestamp) = commitment.bestFinalizedBid();
    assertEq(bestVol, 97);
  }
}
