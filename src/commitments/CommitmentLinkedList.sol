// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";
import "./DynamicArrayLib.sol";
import "./LinkedListLib.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "src/interfaces/IAccount.sol";
import "../interfaces/IAsset.sol";
import "../../test/shared/mocks/MockAsset.sol";

contract CommitmentLinkedList {
  using DynamicArrayLib for uint96[];
  using LinkedListLib for SortedList;

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
  }

  struct Node {
    uint64 nodeId;
    uint64 totalDeposit;
    uint64 depositLeft;
    uint accountId;
  }

  // sorted list sorting vol from low to high
  // for bid: we go from end to find the highest
  // for ask: we go from head to find the lowest
  struct SortedList {
    mapping(uint16 => VolEntity) entities;
    uint16 length;
    uint16 head;
    uint16 end;
  }

  struct VolEntity {
    uint16 vol;
    uint16 prev;
    uint16 next;
    uint64 totalWeight;
    uint64 epoch;
    bool initialized;
    Participant[] participants;
  }

  struct Participant {
    uint64 nodeId;
    uint64 weight;
  }

  // only 0 ~ 1 is used
  // pending/collecting => subid => queue
  mapping(uint8 => mapping(uint96 => SortedList)) public bidQueues;
  mapping(uint8 => mapping(uint96 => SortedList)) public askQueues;

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

  uint64 public epoch;

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

  function pendingBidListInfo(uint96 subId) external view returns (uint16 head, uint16 end, uint16 length_) {
    head = bidQueues[PENDING][subId].head;
    end = bidQueues[PENDING][subId].end;
    length_ = bidQueues[PENDING][subId].length;
  }

  function pendingAskListInfo(uint96 subId) external view returns (uint16 head, uint16 end, uint16 length_) {
    head = askQueues[PENDING][subId].head;
    end = askQueues[PENDING][subId].end;
    length_ = bidQueues[PENDING][subId].length;
  }

  function collectingBidListInfo(uint96 subId) external view returns (uint16 head, uint16 end, uint16 length_) {
    head = bidQueues[COLLECTING][subId].head;
    end = bidQueues[COLLECTING][subId].end;
    length_ = bidQueues[COLLECTING][subId].length;
  }

  function collectingAskListInfo(uint96 subId) external view returns (uint16 head, uint16 end, uint16 length_) {
    head = askQueues[COLLECTING][subId].head;
    end = askQueues[COLLECTING][subId].end;
    length_ = askQueues[COLLECTING][subId].length;
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
  function executeCommit(uint96 subId, bool isBid, uint16 vol, uint16 weight) external {
    (uint8 cachePENDING,) = _checkRollover();

    if (isBid) {
      SortedList storage list = bidQueues[cachePENDING][subId];
      // VolEntity storage target = list.entities[vol];
      list.removeWeightFromVolList(vol, weight);
    } else {
      SortedList storage list = askQueues[cachePENDING][subId];
      // VolEntity storage target = list.entities[vol];
      list.removeWeightFromVolList(vol, weight);
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
    bidQueues[cacheCOLLECTING][subId].addParticipantToLinkedList(bidVol, weight, node, epoch);
    askQueues[cacheCOLLECTING][subId].addParticipantToLinkedList(askVol, weight, node, epoch);

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

    epoch += 1;

    return (cacheCOLLECTING, cachePENDING);
  }

  function _updateFromPendingForEachSubId(uint8 _indexPENDING) internal {
    uint96[] memory subIds_ = subIds[_indexPENDING];

    for (uint i; i < subIds_.length; i++) {
      uint96 subId = subIds_[i];
      SortedList storage bidList = bidQueues[_indexPENDING][subId];

      SortedList storage askList = askQueues[_indexPENDING][subId];

      // return head of bid
      bestFinalizedBids[subId] = FinalizedQuote(bidList.end, bidList.entities[bidList.end].totalWeight);

      bestFinalizedAsks[subId] = FinalizedQuote(askList.head, askList.entities[askList.head].totalWeight);

      bidList.clearList();
      askList.clearList();
    }
  }
}
