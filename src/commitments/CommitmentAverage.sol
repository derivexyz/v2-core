// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";

/**
 * 3 Blocks to aggregate vol submited
 * * ------------- * ------------- * ------------- *
 * |   Finalized   |    Pending    |   Collecting  |
 * * ------------- * ------------- * ------------- *
 */
contract CommitmentAverage {
  error No_Pending_Commitment();

  struct AvgCommitment {
    uint16 bidVol;
    uint16 askVol;
    uint16 weight;
    uint64 timestamp;
  }

  uint8 public FINALIZED = 2;
  uint8 public PENDING = 1;
  uint8 public COLLECTING = 0;

  AvgCommitment[3] public state;

  mapping(uint8 => mapping(uint16 => AvgCommitment)) commitments;

  uint16 constant RANGE = 5;

  constructor() {}

  /// @dev commit to the 'collecting' block
  function commit(uint16 vol, uint16 node, uint16 weight) external {
    // todo: cannot double commit;
    // todo: check sender node id

    _checkRotateBlocks();

    (uint16 bidVol, uint16 askVol) = (vol - RANGE, vol + RANGE);

    AvgCommitment memory collecting = state[COLLECTING];
    uint16 newWeight = weight + collecting.weight;

    state[COLLECTING].bidVol = ((bidVol * weight) + (collecting.bidVol * collecting.weight)) / (newWeight);

    state[COLLECTING].askVol = ((askVol * weight) + (collecting.askVol * collecting.weight)) / (newWeight);

    state[COLLECTING].weight = newWeight;
    state[COLLECTING].timestamp = uint64(block.timestamp);

    commitments[COLLECTING][node] = AvgCommitment(bidVol, askVol, weight, uint64(block.timestamp));
  }

  /// @dev commit to the 'collecting' block
  function executeCommit(uint16 node, uint16 weight) external {
    _checkRotateBlocks();

    AvgCommitment memory nodeCommit = commitments[PENDING][node];

    if (nodeCommit.timestamp == 0) revert No_Pending_Commitment();

    AvgCommitment memory avgCollecting = state[PENDING];
    uint16 newWeight = avgCollecting.weight - weight;

    if (newWeight == 0) {
      delete state[PENDING];
    } else {
      state[PENDING].bidVol =
        ((avgCollecting.bidVol * avgCollecting.weight) - (nodeCommit.bidVol * weight)) / (newWeight);
      state[PENDING].askVol =
        ((avgCollecting.askVol * avgCollecting.weight) - (nodeCommit.askVol * weight)) / (newWeight);
      state[PENDING].weight = newWeight;
    }

    if (weight == nodeCommit.weight) {
      delete commitments[PENDING][node];
    } else {
      commitments[PENDING][node].weight = nodeCommit.weight - weight;
    }

    // trade;
  }

  function _checkRotateBlocks() internal {
    AvgCommitment storage pending = state[PENDING];

    // has been exeucting for 5 mins, push to finalized
    if (pending.timestamp + 5 minutes < block.timestamp) {
      // delete finalized state, put state
      delete state[FINALIZED];

      (FINALIZED, PENDING, COLLECTING) = (PENDING, COLLECTING, FINALIZED);
    }
  }
}
