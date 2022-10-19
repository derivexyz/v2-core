// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";

/**
 * 3 Blocks to aggregate vol submited
 *
 */
contract CommitmentBest {
  error NotExecutable();

  struct Commitment {
    uint16 bidVol;
    uint16 askVol;
    uint16 nodeId;
    uint16 commitments;
    uint64 timestamp;
    bool isExecuted;
  }

  Commitment[256] public queue;

  uint8 lastUnprocessedIndex;
  uint8 lastIndex;

  uint16 public currentBestBid;
  uint16 public currentBestAsk;
  uint64 public currentBestBidTimestamp;
  uint64 public currentBestAskTimestamp;

  // mapping(uint8 => mapping(uint16 => Commitment)) commitments;

  uint16 constant RANGE = 5;

  constructor() {}

  /// @dev commit to the 'collecting' block
  function commit(uint16 vol, uint16 node, uint16 weight) external {
    // todo: cannot double commit;
    // todo: check sender node id

    (, uint8 newIndex) = _processQueue();

    queue[newIndex] = Commitment(vol - RANGE, vol + RANGE, node, weight, uint64(block.timestamp), false);

    lastIndex = newIndex;
  }

  /// @dev commit to the 'collecting' block
  function executeCommit(uint16 index, uint16 weight) external {
    _processQueue();

    // can only execute pending commitment.
    Commitment memory commitment = queue[index];
    if (block.timestamp - commitment.timestamp > 5 minutes) revert NotExecutable();

    if (weight == commitment.commitments) {
      queue[index].isExecuted = true;
    } else {
      queue[index].commitments = commitment.commitments - weight;
    }

    // trade;
  }

  function proccesQueue() external {
    _processQueue();
  }

  function _processQueue() internal returns (uint8 lastProcessed, uint8 newIndex) {
    // get all commits more than 5 minutes
    (uint8 cachedLastUnproccessed, uint8 cacheCurrentIndex) = (lastUnprocessedIndex, lastIndex);
    newIndex = cacheCurrentIndex + 1;
    if (newIndex == type(uint8).max) newIndex = 0;

    if (cachedLastUnproccessed == cacheCurrentIndex) {
      return (cachedLastUnproccessed, newIndex);
    }

    (uint16 cacheBestBid, uint16 cacheBestAsk, uint64 cacheBestBidTime, uint64 cacheBestAskTime) =
      (currentBestBid, currentBestAsk, currentBestBidTimestamp, currentBestAskTimestamp);

    (bool updateBid, bool updateAsk) = (false, false);
    unchecked {
      // let i overflow to 0
      for (; cachedLastUnproccessed <= cacheCurrentIndex; cachedLastUnproccessed++) {
        Commitment memory cache = queue[cachedLastUnproccessed];

        if (block.timestamp - cache.timestamp < 5 minutes) break;

        if (cache.isExecuted) continue;

        if (cache.bidVol > cacheBestBid) {
          updateBid = true;
          cacheBestBid = cache.bidVol;
          cacheBestBidTime = cache.timestamp;
        }

        if (cacheBestAsk == 0 || cache.askVol < cacheBestAsk) {
          updateAsk = true;
          cacheBestAsk = cache.askVol;
          cacheBestAskTime = cache.timestamp;
        }
      }
    }

    if (updateBid) {
      currentBestBid = cacheBestBid;
      currentBestBidTimestamp = cacheBestBidTime;
    }

    if (updateAsk) {
      currentBestAsk = cacheBestAsk;
      currentBestAskTimestamp = cacheBestAskTime;
    }

    lastUnprocessedIndex = cachedLastUnproccessed;

    return (cachedLastUnproccessed, newIndex);
  }
}
