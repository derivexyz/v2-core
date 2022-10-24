// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";
import "./DynamicArrayLib.sol";

contract CommitmentBest {
  using DynamicArrayLib for uint96[];

  error NotExecutable();

  error Registered();

  struct Commitment {
    uint16 bidVol;
    uint16 askVol;
    uint16 weight;
    uint64 nodeId;
    uint64 timestamp;
    bool isExecuted;
    uint96 subId;
  }

  struct FinalizedQuote {
    uint16 bestVol;
    uint16 weight;
    uint64 nodeId;
    uint64 bidTimestamp;
  }

  struct Node {
    uint16 totalWeight;
    uint64 nodeId;
  }

  // only 0 ~ 1 is used
  mapping(uint8 => mapping(uint96 => Commitment[])) public queues;

  /// @dev weight[queueIndex][]
  mapping(uint8 => mapping(uint96 => uint16)) public weights;

  /// @dev subIds
  mapping(uint8 => uint96[]) public subIds;

  // subId => [] lengths of queue;
  uint8[2] public length;

  mapping(address => Node) public nodes;

  uint64 nextId = 1;

  mapping(uint96 => FinalizedQuote) public bestFinalizedBids;
  mapping(uint96 => FinalizedQuote) public bestFinalizedAsks;

  uint8 public COLLECTING = 0;
  uint8 public PENDING = 1;

  uint64 pendingStartTimestamp;
  uint64 collectingStartTimestamp;

  constructor() {}

  function pendingLength() external view returns (uint) {
    return length[PENDING];
  }

  function collectingLength() external view returns (uint) {
    return length[COLLECTING];
  }

  function pendingWeight(uint96 subId) external view returns (uint) {
    return weights[PENDING][subId];
  }

  function collectingWeight(uint96 subId) external view returns (uint) {
    return weights[COLLECTING][subId];
  }

  function register() external returns (uint64 id) {
    if (nodes[msg.sender].nodeId != 0) revert Registered();

    id = ++nextId;
    nodes[msg.sender] = Node(0, id);
  }

  /// @dev commit to the 'collecting' block
  function commit(uint96 subId, uint16 bidVol, uint16 askVol, uint16 weight) external {
    (, uint8 cacheCOLLECTING) = _checkRollover();

    uint64 node = nodes[msg.sender].nodeId;

    _addCommitToQueue(cacheCOLLECTING, node, subId, bidVol, askVol, weight);

    length[cacheCOLLECTING] += 1;

    // todo: update collectingStartTimestamp in check rollover if it comes with commits
    if (collectingStartTimestamp == 0) collectingStartTimestamp = uint64(block.timestamp);
  }

  function commitMultiple(
    uint96[] calldata _subIds,
    uint16[] calldata _bidVols,
    uint16[] calldata _askVols,
    uint16[] calldata _weights
  ) external {
    (, uint8 cacheCOLLECTING) = _checkRollover();

    uint valueLength = _subIds.length;
    if (_bidVols.length != valueLength || _askVols.length != valueLength || _weights.length != valueLength) {
      revert("bad inputs");
    }

    uint64 node = nodes[msg.sender].nodeId;

    for (uint i = 0; i < valueLength; i++) {
      _addCommitToQueue(cacheCOLLECTING, node, _subIds[i], _bidVols[i], _askVols[i], _weights[i]);
    }

    length[cacheCOLLECTING] += uint8(valueLength);

    // todo: update collectingStartTimestamp in check rollover if it comes with commits
    if (collectingStartTimestamp == 0) collectingStartTimestamp = uint64(block.timestamp);
  }

  /// @dev commit to the 'collecting' block
  function executeCommit(uint96 subId, uint16 index, uint16 weight) external {
    (uint8 cachePENDING,) = _checkRollover();

    Commitment memory target = queues[cachePENDING][subId][index];

    // update weight for the commit;
    uint16 newWeight = target.weight - weight;
    if (newWeight == 0) {
      queues[cachePENDING][subId][index].isExecuted = true;
      queues[cachePENDING][subId][index].weight = 0;
    } else {
      queues[cachePENDING][subId][index].weight = newWeight;
    }

    // update total weight for an subId
    uint16 newTotalSubIdWeight = weights[cachePENDING][target.subId] - weight;
    if (newTotalSubIdWeight != 0) {
      weights[cachePENDING][target.subId] = newTotalSubIdWeight;
    } else {
      weights[cachePENDING][target.subId] = 0;
      subIds[cachePENDING].removeFromArray(target.subId);
    }

    // trade;
  }

  function _addCommitToQueue(
    uint8 cacheCOLLECTING,
    uint64 node,
    uint96 subId,
    uint16 bidVol,
    uint16 askVol,
    uint16 weight
  ) internal {
    subIds[cacheCOLLECTING].addUniqueToArray(subId);
    weights[cacheCOLLECTING][subId] += weight;

    queues[cacheCOLLECTING][subId].push(Commitment(bidVol, askVol, weight, node, uint64(block.timestamp), false, subId));
  }

  function checkRollover() external {
    _checkRollover();
  }

  function _checkRollover() internal returns (uint8 newPENDING, uint8 newCOLLECTING) {
    // Commitment[256] storage pendingQueue = queue[PENDING];

    (uint8 cachePENDING, uint8 cacheCOLLECTING) = (PENDING, COLLECTING);

    // nothing pending and there are something in the collecting phase:
    // make sure oldest one is older than 5 minutes, if so, move collecting => pending
    if (pendingStartTimestamp == 0) {
      if (collectingStartTimestamp != 0 && block.timestamp - collectingStartTimestamp > 5 minutes) {
        (cachePENDING, cacheCOLLECTING) = _rollOverCollecting(cachePENDING, cacheCOLLECTING);
      }
    }

    // nothing pending and there are something in the collecting phase:
    // make sure oldest one is older than 5 minutes, if so, move collecting => pending
    if (length[cachePENDING] > 0) {
      if (block.timestamp - pendingStartTimestamp < 5 minutes) return (cachePENDING, cacheCOLLECTING);

      _updateFromPendingForEachSubId(cachePENDING);
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

  function _updateFromPendingForEachSubId(uint8 _indexPENDING) internal {
    uint96[] memory subIds_ = subIds[_indexPENDING];

    for (uint i; i < subIds_.length; i++) {
      uint96 subId = subIds_[i];
      Commitment[] memory pendingQueue = queues[_indexPENDING][subId];

      uint16 cacheBestBid;
      uint8 bestBidId;
      uint16 cacheBestAsk;
      uint8 bestAskId;

      for (uint8 j; j < pendingQueue.length; j++) {
        Commitment memory cache = pendingQueue[j];

        if (cache.isExecuted) continue;

        if (cache.bidVol > cacheBestBid) {
          cacheBestBid = cache.bidVol;
          bestBidId = j;
        }

        if (cacheBestAsk == 0 || cache.askVol < cacheBestAsk) {
          cacheBestAsk = cache.askVol;
          bestAskId = j;
        }
      }

      // update subId best
      if (pendingQueue[bestBidId].weight != 0) {
        bestFinalizedBids[subId] = FinalizedQuote(
          cacheBestBid,
          pendingQueue[bestBidId].weight,
          pendingQueue[bestBidId].nodeId,
          pendingQueue[bestBidId].timestamp
        );
      }
      if (pendingQueue[bestAskId].weight != 0) {
        bestFinalizedAsks[subId] = FinalizedQuote(
          cacheBestAsk,
          pendingQueue[bestAskId].weight,
          pendingQueue[bestAskId].nodeId,
          pendingQueue[bestAskId].timestamp
        );
      }
    }
  }
}
