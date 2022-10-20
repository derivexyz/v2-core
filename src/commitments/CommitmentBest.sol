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
  function commit(uint16 node, uint16 vol, uint16 weight) external {
    // todo: cannot double commit;
    // todo: check sender node id
    (, uint8 cacheCOLLECTING) = _checkRollover();

    uint8 newIndex = length[cacheCOLLECTING];

    queue[cacheCOLLECTING][newIndex] =
      Commitment(vol - RANGE, vol + RANGE, node, weight, uint64(block.timestamp), false);

    length[cacheCOLLECTING] = newIndex + 1;
  }

  /// @dev commit to the 'collecting' block
  function executeCommit(uint16 index, uint16 weight) external {
    (uint8 cachePENDING,) = _checkRollover();

    uint16 newWeight = queue[cachePENDING][index].commitments - weight;

    if (newWeight == 0) {
      queue[cachePENDING][index].isExecuted = true;
      queue[cachePENDING][index].commitments = 0;
    } else {
      queue[cachePENDING][index].commitments = newWeight;
    }

    // trade;
  }

  function checkRollover() external {
    _checkRollover();
  }

  function _checkRollover() internal returns (uint8 newPENDING, uint8 newCOLLECTING) {
    // Commitment[256] storage pendingQueue = queue[PENDING];

    (uint8 cachePENDING, uint8 cacheCOLLECTING) = (PENDING, COLLECTING);

    // nothing pending and there are something in the collecting phase: 
    // make sure oldest one is older than 5 minutes, if so, move collecting => pending
    if (length[cachePENDING] == 0 && length[cacheCOLLECTING] != 0) {
      Commitment memory oldest = queue[cacheCOLLECTING][0];
      if (block.timestamp - oldest.timestamp > 5 minutes) {
        (cachePENDING, cacheCOLLECTING) = _rollOverCollecting(cachePENDING, cacheCOLLECTING);
      }
      return (cachePENDING, cacheCOLLECTING);
    }

    // nothing pending and there are something in the collecting phase: 
    // make sure oldest one is older than 5 minutes, if so, move collecting => pending
    if (length[cachePENDING] > 0) {
      if (block.timestamp - pendingStartTimestamp < 5 minutes) return (cachePENDING, cacheCOLLECTING);

      (FinalizedQuote memory bestBid, FinalizedQuote memory bestAsk) = _getBestFromPending(cachePENDING);

      if (bestBid.commitments != 0) {
        bestFinalizedBid = bestBid;
      }
      if (bestAsk.commitments != 0) {
        bestFinalizedAsk = bestAsk;
      }
      (cachePENDING, cacheCOLLECTING) = _rollOverCollecting(cachePENDING, cacheCOLLECTING);
    }

    return (cachePENDING, cacheCOLLECTING);
  }

  function _rollOverCollecting(uint8 cachePENDING, uint8 cacheCOLLECTING)
    internal
    returns (uint8 newPENDING, uint8 newCOLLECTING)
  {
    (COLLECTING, PENDING) = (cachePENDING, cacheCOLLECTING);

    pendingStartTimestamp = uint64(block.timestamp);

    // dont override the array with 0. just reset length
    delete length[cachePENDING]; // delete the length for "new collecting"

    return (cacheCOLLECTING, cachePENDING);
  }

  function _getBestFromPending(uint8 _indexPENDING)
    internal
    view
    returns (FinalizedQuote memory _bestBid, FinalizedQuote memory _bestAsk)
  {
    Commitment[256] memory pendingQueue = queue[_indexPENDING];

    (uint16 cacheBestBid, uint16 cacheBestAsk, uint8 bestBidId, uint8 bestAskId) = (0, 0, 0, 0);

    unchecked {
      for (uint8 i; i < length[_indexPENDING]; i++) {
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
