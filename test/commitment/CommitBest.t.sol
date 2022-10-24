// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "src/commitments/CommitmentBest.sol";

contract UNIT_CommitBest is Test {
  CommitmentBest commitment;
  uint16 constant commitmentWeight = 1;

  uint96 subId = 1;

  constructor() {
    commitment = new CommitmentBest();

    commitment.register();

    vm.warp(block.timestamp + 1 days);
  }

  function testCanCommit() public {
    commitment.commit(subId, 100, commitmentWeight);
    commitment.commit(subId, 100, commitmentWeight);
    commitment.commit(subId, 102, commitmentWeight);
    commitment.commit(subId, 105, commitmentWeight);

    vm.warp(block.timestamp + 10 minutes);

    commitment.checkRollover();

    assertEq(commitment.pendingLength(), 4);
    assertEq(commitment.collectingLength(), 0);
  }

  function testCanExecuteCommit() public {
    commitment.commit(subId, 100, commitmentWeight); // collecting: 1, pending: 0
    commitment.commit(subId, 104, commitmentWeight); // collecting: 2, pending: 0
    commitment.commit(subId, 102, commitmentWeight); // collecting: 3, pending: 0
    assertEq(commitment.collectingLength(), 3);
    assertEq(commitment.collectingWeight(subId), commitmentWeight * 3);

    vm.warp(block.timestamp + 10 minutes);
    commitment.checkRollover();

    assertEq(commitment.pendingLength(), 3);

    commitment.executeCommit(subId, 0, commitmentWeight);
    commitment.executeCommit(subId, 1, commitmentWeight);

    vm.warp(block.timestamp + 10 minutes);
    commitment.checkRollover();

    (uint16 bestVol,,,) = commitment.bestFinalizedBids(subId);
    assertEq(bestVol, 97);
  }

  function testCanExecuteCommitMultiple() public {
    uint96 subId2 = 2;

    uint96[] memory subIds = new uint96[](6);
    subIds[0] = subId;
    subIds[1] = subId;
    subIds[2] = subId;
    subIds[3] = subId2;
    subIds[4] = subId2;
    subIds[5] = subId2;

    uint16[] memory vols = new uint16[](6);
    vols[0] = 100;
    vols[1] = 101;
    vols[2] = 102;
    vols[3] = 103;
    vols[4] = 104;
    vols[5] = 105;

    uint16[] memory weights = new uint16[](6);
    for (uint i; i < 6; i++) {
      weights[i] = commitmentWeight;
    }

    commitment.commitMultiple(subIds, vols, weights);
    assertEq(commitment.collectingLength(), 6);

    vm.warp(block.timestamp + 10 minutes);
    commitment.checkRollover();

    assertEq(commitment.pendingLength(), 6);

    // remove 1st for subId
    commitment.executeCommit(subId, 0, commitmentWeight);

    // remove 1st for subId2
    commitment.executeCommit(subId2, 0, commitmentWeight);

    vm.warp(block.timestamp + 10 minutes);
    commitment.checkRollover();

    (uint16 bestVol,,,) = commitment.bestFinalizedBids(subId);
    assertEq(bestVol, 97);

    (uint16 bestVol2,,,) = commitment.bestFinalizedBids(subId2);
    assertEq(bestVol2, 100);
  }

  function testShouldRolloverBlankIfPendingIsEmpty() public {
    commitment.commit(subId, 100, commitmentWeight); // collecting: 1, pending: 0
    commitment.commit(subId, 104, commitmentWeight); // collecting: 2, pending: 0

    vm.warp(block.timestamp + 10 minutes);
    commitment.checkRollover(); // collecting: 0, pending: 2

    assertEq(commitment.pendingLength(), 2);
    assertEq(commitment.pendingWeight(subId), commitmentWeight * 2);

    commitment.executeCommit(subId, 0, commitmentWeight);
    commitment.executeCommit(subId, 1, commitmentWeight);

    commitment.commit(subId, 100, commitmentWeight); // collecting: 1, pending: 0

    vm.warp(block.timestamp + 10 minutes);

    commitment.checkRollover();

    (uint16 bestVol, uint16 commitments, uint64 nodeId, uint64 bidTimestamp) = commitment.bestFinalizedBids(subId);
    assertEq(bestVol, 0);
    assertEq(nodeId, 0);
    assertEq(commitments, 0);
    assertEq(bidTimestamp, 0);

    assertEq(commitment.pendingLength(), 1);
  }
}
