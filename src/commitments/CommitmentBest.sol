// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";

/**
 * 3 Blocks to aggregate vol submited
 *
 */
contract CommitmentBest {
  struct Commitment {
    uint16 bidVol;
    uint16 askVol;
    uint16 commitments;
    uint64 timestamp;
  }

  Commitment[256] public queue;

  mapping(uint8 => mapping(uint16 => Commitment)) commitments;

  uint16 constant RANGE = 5;

  constructor() {}

  /// @dev commit to the 'collecting' block
  function commit(uint16 vol, uint16 node, uint16 weight) external {
    // todo: cannot double commit;
    // todo: check sender node id

    _processQueue();

    (uint16 bidVol, uint16 askVol) = (vol - RANGE, vol + RANGE);
  }

  function _processQueue() internal {
    // get all commits more than 5 minutes
  }
}
