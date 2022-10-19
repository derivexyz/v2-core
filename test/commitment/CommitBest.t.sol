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

    commitment.proccesQueue();

    assertEq(commitment.currentBestBid(), 100);
    assertEq(commitment.currentBestAsk(), 105);
  }

  function testCanExecuteCommit() public {
    commitment.commit(100, 1, commitmentWeight);
    commitment.commit(104, 2, commitmentWeight);
    commitment.commit(102, 3, commitmentWeight);
    commitment.commit(105, 4, commitmentWeight);

    // execute first
    commitment.executeCommit(1, commitmentWeight);
    // execute second
    commitment.executeCommit(2, commitmentWeight);

    vm.warp(block.timestamp + 10 minutes);

    commitment.proccesQueue();

    assertEq(commitment.currentBestBid(), 100);
    assertEq(commitment.currentBestAsk(), 107);
  }
}
