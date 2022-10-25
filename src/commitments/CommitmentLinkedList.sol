// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";
import "./DynamicArrayLib.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "src/interfaces/IAccount.sol";
import "../interfaces/IAsset.sol";
import "../../test/shared/mocks/MockAsset.sol";

contract CommitmentLinkedList {
  using DynamicArrayLib for uint96[];

  error NotExecutable();

  error Registered();
  error NotRegistered();

  struct Commitment {
    uint16 vol;
    uint16 range;
    uint64 weight;
    uint64 nodeId;
    uint64 timestamp;
    bool isExecuted;
  }

  struct FinalizedQuote {
    uint16 bestVol;
    uint64 weight;
    uint64 nodeId;
    uint64 timestamp;
  }

  struct Node {
    uint64 nodeId;
    uint64 totalDeposit;
    uint64 depositLeft;
    uint accountId;
  }

  // only 0 ~ 1 is used
  // pending/collecting => subid => queue
  mapping(uint8 => mapping(uint96 => Commitment[])) public bidQueues;
  mapping(uint8 => mapping(uint96 => Commitment[])) public askQueues;

  /// @dev pending/collecting => subid => totalWeights
  mapping(uint8 => mapping(uint96 => uint64)) public weights;

  /// @dev pending/collecting => subid
  mapping(uint8 => uint96[]) public subIds;

  // subId => [] total lengths of queue;
  uint32[2] public length;

  mapping(address => Node) public nodes;

  uint64 nextId = 1;

  mapping(uint96 => FinalizedQuote) public bestFinalizedBids;
  mapping(uint96 => FinalizedQuote) public bestFinalizedAsks;

  uint8 public COLLECTING = 0;
  uint8 public PENDING = 1;

  uint64 pendingStartTimestamp;
  uint64 collectingStartTimestamp;

  address immutable quote;
  address immutable quoteAsset;
  address immutable account;
  address immutable manager;

  constructor(address _account, address _quote, address _quoteAsset, address _manager) {
    account = _account;
    quoteAsset = _quoteAsset;
    quote = _quote;
    manager = _manager;
    IERC20(_quote).approve(quoteAsset, type(uint).max);
  }

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

  function register() external returns (uint64 nodeId) {
    if (nodes[msg.sender].nodeId != 0) revert Registered();

    nodeId = ++nextId;

    // create accountId and
    uint accountId = IAccount(account).createAccount(address(this), IManager(manager));

    nodes[msg.sender] = Node(nodeId, 0, 0, accountId);
  }

  function deposit(uint64 amount) external {
    if (nodes[msg.sender].nodeId == 0) revert NotRegistered();
    IERC20(quote).transferFrom(msg.sender, address(this), amount);
    MockAsset(quoteAsset).deposit(nodes[msg.sender].accountId, 0, amount);

    nodes[msg.sender].totalDeposit += amount;
    nodes[msg.sender].depositLeft += amount;
  }

  /// @dev commit to the 'collecting' block
  function commit(uint96 subId, uint16 bidVol, uint16 askVol, uint64 weight) external {
    (, uint8 cacheCOLLECTING) = _checkRollover();

    uint64 node = nodes[msg.sender].nodeId;

    _addCommitToQueue(cacheCOLLECTING, msg.sender, node, subId, bidVol, askVol, weight);

    length[cacheCOLLECTING] += 1;

    // todo: update collectingStartTimestamp in check rollover if it comes with commits
    if (collectingStartTimestamp == 0) collectingStartTimestamp = uint64(block.timestamp);
  }

  function commitMultiple(
    uint96[] calldata _subIds,
    uint16[] calldata _bidVols,
    uint16[] calldata _askVols,
    uint64[] calldata _weights
  ) external {
    (, uint8 cacheCOLLECTING) = _checkRollover();

    uint valueLength = _subIds.length;
    if (_bidVols.length != valueLength || _askVols.length != valueLength || _weights.length != valueLength) {
      revert("bad inputs");
    }

    uint64 node = nodes[msg.sender].nodeId;

    for (uint i = 0; i < valueLength; i++) {
      _addCommitToQueue(cacheCOLLECTING, msg.sender, node, _subIds[i], _bidVols[i], _askVols[i], _weights[i]);
    }

    length[cacheCOLLECTING] += uint8(valueLength);

    // todo: update collectingStartTimestamp in check rollover if it comes with commits
    if (collectingStartTimestamp == 0) collectingStartTimestamp = uint64(block.timestamp);
  }

  /// @dev commit to the 'collecting' block
  function executeCommit(uint96 subId, bool isBid, uint16 index, uint16 weight) external {
    (uint8 cachePENDING,) = _checkRollover();

    if (isBid) {
      Commitment memory target = bidQueues[cachePENDING][subId][index];
      uint64 newWeight = target.weight - weight;
      if (newWeight == 0) {
        bidQueues[cachePENDING][subId][index].isExecuted = true;
        bidQueues[cachePENDING][subId][index].weight = 0;
      } else {
        bidQueues[cachePENDING][subId][index].weight = newWeight;
      }
    } else {
      Commitment memory target = askQueues[cachePENDING][subId][index];
      uint64 newWeight = target.weight - weight;
      if (newWeight == 0) {
        askQueues[cachePENDING][subId][index].isExecuted = true;
        askQueues[cachePENDING][subId][index].weight = 0;
      } else {
        askQueues[cachePENDING][subId][index].weight = newWeight;
      }
    }

    // update total weight for an subId
    uint64 newTotalSubIdWeight = weights[cachePENDING][subId] - weight;
    if (newTotalSubIdWeight != 0) {
      weights[cachePENDING][subId] = newTotalSubIdWeight;
    } else {
      weights[cachePENDING][subId] = 0;
      subIds[cachePENDING].removeFromArray(subId);
    }

    // trade;
  }

  function _addCommitToQueue(
    uint8 cacheCOLLECTING,
    address owner,
    uint64 node,
    uint96 subId,
    uint16 bidVol,
    uint16 askVol,
    uint64 weight
  ) internal {
    subIds[cacheCOLLECTING].addUniqueToArray(subId);
    weights[cacheCOLLECTING][subId] += weight;

    // add to both bid and ask queue with the same collateral
    bidQueues[cacheCOLLECTING][subId].push(
      Commitment(bidVol, askVol - bidVol, weight, node, uint64(block.timestamp), false)
    );
    askQueues[cacheCOLLECTING][subId].push(
      Commitment(askVol, askVol - bidVol, weight, node, uint64(block.timestamp), false)
    );

    nodes[owner].depositLeft -= weight;
  }

  function checkRollover() external {
    _checkRollover();
  }

  function _checkRollover() internal returns (uint8 newPENDING, uint8 newCOLLECTING) {
    // Commitment[256] storage pendingQueue = queue[PENDING];

    (uint8 cachePENDING, uint8 cacheCOLLECTING) = (PENDING, COLLECTING);

    /// if no pending: check we need to put collecting to pending
    if (pendingStartTimestamp == 0 || length[cachePENDING] == 0) {
      if (collectingStartTimestamp != 0 && block.timestamp - collectingStartTimestamp > 5 minutes) {
        // console2.log("roll over! change pending vs collecting");
        (cachePENDING, cacheCOLLECTING) = _rollOverCollecting(cachePENDING, cacheCOLLECTING);
        return (cachePENDING, cacheCOLLECTING);
      }
    }

    // nothing pending and there are something in the collecting phase:
    // make sure oldest one is older than 5 minutes, if so, move collecting => pending
    if (length[cachePENDING] > 0) {
      // console2.log("check if need to update finalized");
      if (block.timestamp - pendingStartTimestamp < 5 minutes) return (cachePENDING, cacheCOLLECTING);

      _updateFromPendingForEachSubId(cachePENDING);
      // console2.log("roll over! already update pending => finalized");
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
      Commitment[] memory pendingBids = bidQueues[_indexPENDING][subId];

      // handle bids
      uint16 cacheBestBid;
      uint8 bestBidId;
      for (uint8 j; j < pendingBids.length; j++) {
        Commitment memory cache = pendingBids[j];

        if (cache.isExecuted) continue;

        if (cache.vol > cacheBestBid) {
          cacheBestBid = cache.vol;
          bestBidId = j;
        }
      }
      // update subId best bid
      if (pendingBids[bestBidId].weight != 0) {
        bestFinalizedBids[subId] = FinalizedQuote(
          cacheBestBid, pendingBids[bestBidId].weight, pendingBids[bestBidId].nodeId, pendingBids[bestBidId].timestamp
        );
      }

      // handle asks
      uint16 cacheBestAsk;
      uint8 bestAskId;
      Commitment[] memory pendingAsks = askQueues[_indexPENDING][subId];
      for (uint8 j; j < pendingAsks.length; j++) {
        Commitment memory cache = pendingAsks[j];

        if (cache.isExecuted) continue;

        if (cacheBestAsk == 0 || cache.vol < cacheBestAsk) {
          cacheBestAsk = cache.vol;
          bestAskId = j;
        }
      }
      if (pendingAsks[bestAskId].weight != 0) {
        // console2.log("find ask for subId <3", subId, cacheBestAsk);
        bestFinalizedAsks[subId] = FinalizedQuote(
          cacheBestAsk, pendingAsks[bestAskId].weight, pendingAsks[bestAskId].nodeId, pendingAsks[bestAskId].timestamp
        );
      }
    }
  }
}
