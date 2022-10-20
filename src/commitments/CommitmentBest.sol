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

  struct FinalizedQuote {
    uint16 bestVol;
    uint16 nodeId;
    uint16 commitments;
    uint64 bidTimestamp;
  }

  // only 0 ~ 1 is used
  Commitment[256][2] public queue;

  FinalizedQuote public bestFinalizedBid;
  FinalizedQuote public bestFinalizedAsk;

  uint8 public COLLECTING = 0;
  uint8 public PENDING = 1;

  uint8[3] public length;

  uint64 pendingStartTimestamp;

  uint16 constant RANGE = 5;

  constructor() {}

  function pendingLength() external view returns (uint) {
    return length[PENDING];
  }

  function collectingLength() external view returns (uint) {
    return length[COLLECTING];
  }

  /// @dev commit to the 'collecting' block
  function commit(uint16 vol, uint16 node, uint16 weight) external {
    // todo: cannot double commit;
    // todo: check sender node id
    _checkRollover();

    uint8 newIndex = length[COLLECTING];

    queue[COLLECTING][newIndex] = Commitment(vol - RANGE, vol + RANGE, node, weight, uint64(block.timestamp), false);

    length[COLLECTING] = newIndex + 1;
  }

  /// @dev commit to the 'collecting' block
  function executeCommit(uint16 index, uint16 weight) external {
    _checkRollover();

    uint16 newWeight = queue[PENDING][index].commitments - weight;

    if (newWeight == 0) {
      console2.log("execute");
      queue[PENDING][index].isExecuted = true;
    } else {
      queue[PENDING][index].commitments = newWeight;
    }

    // trade;
  }

  function checkRollover() external {
    _checkRollover();
  }

  function _checkRollover() internal {
    // Commitment[256] storage pendingQueue = queue[PENDING];

    // first iteration: pending length is empty
    if (length[PENDING] == 0 && length[COLLECTING] != 0) {
      Commitment memory oldest = queue[COLLECTING][0];
      if (block.timestamp - oldest.timestamp > 5 minutes) {
        _rollOverCollecting();
      }
      return;
    }

    if (length[PENDING] > 0) {
      if (block.timestamp - pendingStartTimestamp < 5 minutes) return;

      (FinalizedQuote memory bestBid, FinalizedQuote memory bestAsk) = _getBestFromPending();

      if (bestBid.commitments != 0) {
        bestFinalizedBid = bestBid;
      }
      if (bestAsk.commitments != 0) {
        bestFinalizedAsk = bestAsk;
      }
      _rollOverCollecting();
    }
  }

  function _rollOverCollecting() internal {
    console2.log("rollover!");
    (COLLECTING, PENDING) = (PENDING, COLLECTING);

    pendingStartTimestamp = uint64(block.timestamp);

    delete length[COLLECTING];
    delete queue[COLLECTING];
  }

  function _getBestFromPending() internal view returns (FinalizedQuote memory _bestBid, FinalizedQuote memory _bestAsk) {
    // get all commits more than 5 minutes

    Commitment[256] memory pendingQueue = queue[PENDING];

    (uint16 cacheBestBid, uint16 cacheBestAsk, uint8 bestBidId, uint8 bestAskId) = (0, 0, 0, 0);

    unchecked {
      // let i overflow to 0
      for (uint8 i; i < length[PENDING]; i++) {
        Commitment memory cache = pendingQueue[i];

        if (cache.isExecuted) continue;

        if (cache.bidVol > cacheBestBid) {
          cacheBestBid = cache.bidVol;
          bestBidId = i;
        }

        if (cacheBestAsk == 0 || cache.askVol < cacheBestAsk) {
          cacheBestAsk = cache.askVol;
          bestAskId = i;
        }
      }
    }

    return (
      FinalizedQuote(
        pendingQueue[bestBidId].bidVol,
        pendingQueue[bestBidId].nodeId,
        pendingQueue[bestBidId].commitments,
        pendingQueue[bestBidId].timestamp
        ),
      FinalizedQuote(
        pendingQueue[bestAskId].askVol,
        pendingQueue[bestAskId].nodeId,
        pendingQueue[bestAskId].commitments,
        pendingQueue[bestAskId].timestamp
        )
    );
  }
}
