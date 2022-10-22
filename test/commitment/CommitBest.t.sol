// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "src/commitments/CommitmentBest.sol";

contract UNIT_CommitBest is Test {
  CommitmentBest commitment;
  uint16 constant commitmentWeight = 1;

  uint96 subId = 1;

  modifier SingleSubId() {
    _;
  }

  constructor() {
    commitment = new CommitmentBest();

    commitment.register();

    vm.warp(block.timestamp + 1 days);
  }

  function testCanCommit() public SingleSubId {
    commitment.commit(subId, 100, commitmentWeight);
    commitment.commit(subId, 100, commitmentWeight);
    commitment.commit(subId, 102, commitmentWeight);
    commitment.commit(subId, 105, commitmentWeight);

    vm.warp(block.timestamp + 10 minutes);

    commitment.checkRollover();

    assertEq(commitment.pendingLength(), 4);
    assertEq(commitment.collectingLength(), 0);
  }

  function testCanExecuteCommit() public SingleSubId {
    commitment.commit(subId, 100, commitmentWeight); // collecting: 1, pending: 0
    commitment.commit(subId, 104, commitmentWeight); // collecting: 2, pending: 0
    commitment.commit(subId, 102, commitmentWeight); // collecting: 3, pending: 0
    assertEq(commitment.collectingLength(), 3);

    vm.warp(block.timestamp + 10 minutes);
    commitment.checkRollover();

    assertEq(commitment.pendingLength(), 3);

    commitment.executeCommit(0, commitmentWeight);
    commitment.executeCommit(1, commitmentWeight);

    vm.warp(block.timestamp + 10 minutes);
    commitment.checkRollover();

    (uint16 bestVol,,,) = commitment.bestFinalizedBid();
    assertEq(bestVol, 97);
  }

  function testShouldRolloverBlankIfPendingIsEmpty() public SingleSubId {
    commitment.commit(subId, 100, commitmentWeight); // collecting: 1, pending: 0
    commitment.commit(subId, 104, commitmentWeight); // collecting: 2, pending: 0

    vm.warp(block.timestamp + 10 minutes);
    commitment.checkRollover(); // collecting: 0, pending: 2

    assertEq(commitment.pendingLength(), 2);

    commitment.executeCommit(0, commitmentWeight);
    commitment.executeCommit(1, commitmentWeight);

    commitment.commit(subId, 100, commitmentWeight); // collecting: 1, pending: 0

    vm.warp(block.timestamp + 10 minutes);

    commitment.checkRollover();

    (uint16 bestVol, uint16 commitments, uint64 nodeId, uint64 bidTimestamp) = commitment.bestFinalizedBid();
    assertEq(bestVol, 0);
    assertEq(nodeId, 0);
    assertEq(commitments, 0);
    assertEq(bidTimestamp, 0);

    assertEq(commitment.pendingLength(), 1);
  }
}
