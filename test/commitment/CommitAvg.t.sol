// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "src/commitments/CommitmentAverage.sol";

contract UNIT_CommitAvg is Test {
  CommitmentAverage commitment;

  constructor() {
    commitment = new CommitmentAverage();

    vm.warp(block.timestamp + 1 days);
  }

  function testCanCommit() public {
    commitment.commit(100, 1, 1);

    (uint16 bidVol, uint16 askVol, uint16 totalCommitment,) = commitment.state(commitment.COLLECTING());
    assertEq(bidVol, 95);
    assertEq(askVol, 105);
    assertEq(totalCommitment, 1);

    // this will rotate again -> become only one in COLLECTING

    // firt one committing to pending
    commitment.commit(110, 1, 1);
    // commit another
    commitment.commit(116, 2, 1);
    (uint16 bidVol2, uint16 askVol2,,) = commitment.state(commitment.COLLECTING());

    assertEq(bidVol2, 113 - 5);
    assertEq(askVol2, 113 + 5);
  }

  function testCanExecuteCommit() public {
    commitment.commit(100, 1, 1);
    // this will rotate again -> become only one in COLLECTING

    // firt one committing to pending
    commitment.commit(110, 1, 1);
    commitment.commit(110, 2, 1);
    commitment.commit(116, 3, 1);

    vm.warp(block.timestamp + 10 minutes);
    commitment.executeCommit(3, 1);
    (uint16 bidVol, uint16 askVol, uint16 totalCommitment,) = commitment.state(commitment.PENDING());

    // commitment.executeCommit(1, 1);
    assertEq(bidVol, 105);
    assertEq(askVol, 115);
    assertEq(totalCommitment, 2);

    // trigger another round
    vm.warp(block.timestamp + 10 minutes);
    commitment.commit(110, 1, 1);

    (uint16 bidVolFinal, uint16 askVolFinal,,) = commitment.state(commitment.FINALIZED());
    assertEq(bidVolFinal, 105);
    assertEq(askVolFinal, 115);
    //
  }
}
