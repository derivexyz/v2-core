// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";
import "../interfaces/IAccount.sol";
import "test/account/mocks/assets/lending/Lending.sol";
import "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";


/**
 * 3 Blocks to aggregate vol submited
 * * ------------- * ------------- * ------------- *
 * |   Finalized   |    Pending    |   Collecting  |
 * * ------------- * ------------- * ------------- *
 */
contract CommitmentAverage {
  using SafeCast for uint;

  error No_Pending_Commitment();

  struct NodeCommitment {
    uint16 bidVol; // lets assume [256] listings for now
    uint16 askVol; // todo: still need to figure out forwards / interest
    uint128 weight; // used across all asks
    uint64 timestamp;
  }

  struct State {
    uint16 bidVol;
    uint16 askVol;
    uint128 weight;
  }

  struct Node {
    uint256 deposits;
    uint256 totalWeight;
    uint256 nodeId;
  }

  uint8 public FINALIZED = 2;
  uint8 public PENDING = 1;
  uint8 public COLLECTING = 0;

  mapping(uint8 => State[256]) public state; // EPOCH TYPE -> 256 epoch states 
  uint64[3] public timestamps; // EPOCH TYPE -> timestamp

  // nodeData
  mapping(uint8 => mapping(uint256 => NodeCommitment[256])) public commitments; // epoch -> node -> commitments[], how do these work with rotating epochs
  mapping(address => Node) public nodes;
  uint256 nextNodeId = 1;

  // todo: need to make dynamic range
  uint16 constant public RANGE = 5;
  uint16 constant public DEPOSIT_PER_SUBID = 500;


  // account variables
  Lending lendingAsset;
  uint accountId;
  IERC20 token;

  constructor(address _accountSystem, address _manager, address _lendingAsset, address _token) {
    lendingAsset = Lending(_lendingAsset);
    accountId = IAccount(_accountSystem).createAccount(address(this), IManager(_manager));
    token = IERC20(_token);
    token.approve(address(_lendingAsset), type(uint).max);
  }

  /// @dev allow node to deposit once and reuse deposit everytime
  function deposit(uint256 amount) external {
    token.transferFrom(msg.sender, address(this), amount);

    lendingAsset.deposit(accountId, amount);
    Node memory depositNode = nodes[msg.sender];
    if (depositNode.nodeId == 0) {
      nodes[msg.sender].nodeId = nextNodeId++;
    }

    nodes[msg.sender].deposits += amount;
  }

  /// @dev commit to the 'collecting' block
  function commit(
    uint16[] memory vols, 
    uint8[] memory subIds, 
    uint128[] memory weights
  ) external {
    Node memory commitNode = nodes[msg.sender];

    _checkRotateBlocks();

    uint128 bidVol;
    uint128 askVol;
    for (uint i = 0; i < subIds.length; i++) {
      NodeCommitment memory subIdCommitment = commitments[COLLECTING][commitNode.nodeId][subIds[i]];

      // if commitment in current epoch was made, ignore new commitments
      if (subIdCommitment.weight > 0 && subIdCommitment.timestamp + 5 minutes > block.timestamp) { break; }

      // prevent further commits if not enough deposits made by node
      if (commitNode.deposits < (commitNode.totalWeight + weights[subIds[i]]) * DEPOSIT_PER_SUBID) { 
        break; 
      } else {
        nodes[msg.sender].totalWeight += weights[subIds[i]];
      }

      State memory collecting = state[COLLECTING][subIds[i]]; // get current average
      
      uint128 newWeight = weights[subIds[i]] + collecting.weight;

      // todo: cheaper to just store in one go?
      (bidVol, askVol) = (uint128(vols[i] - RANGE), uint128(vols[i] + RANGE));
      state[COLLECTING][subIds[i]] = State({
        bidVol: SafeCast.toUint16(
          ((bidVol * weights[subIds[i]]) + (uint128(collecting.bidVol) * collecting.weight)) / (newWeight)
        ),
        askVol: SafeCast.toUint16(
          ((askVol * weights[subIds[i]]) + (uint128(collecting.askVol) * collecting.weight)) / (newWeight)
        ),
        weight: newWeight
      });

      commitments[COLLECTING][commitNode.nodeId][subIds[i]] = NodeCommitment(
        SafeCast.toUint16(bidVol), SafeCast.toUint16(askVol), weights[subIds[i]], uint64(block.timestamp)
      );
    }
  }

  /// @dev commit to the 'collecting' block
  function executeCommit(uint16 node, uint128 amount, uint8 subId) external {
    // todo: deal with actual risk manager costs...
    _checkRotateBlocks();

    NodeCommitment memory nodeCommit = commitments[PENDING][node][subId];

    if (nodeCommit.timestamp == 0 || nodeCommit.timestamp + 5 minutes > block.timestamp) revert No_Pending_Commitment();

    State memory avgCollecting = state[PENDING][subId];
    uint128 newWeight = avgCollecting.weight - amount;

    if (newWeight == 0) {
      state[PENDING][subId] = State(0, 0, 0); // clear average no commitments remain
    } else {
      state[COLLECTING][subId] = State({
        bidVol: SafeCast.toUint16((
          (uint128(avgCollecting.bidVol) * avgCollecting.weight) - (uint128(nodeCommit.bidVol) * amount)
        ) / (newWeight)),
        askVol: SafeCast.toUint16((
          (uint128(avgCollecting.askVol) * avgCollecting.weight) - (uint128(nodeCommit.askVol) * amount)
        ) / (newWeight)),
        weight: newWeight
      });
    }

    if (amount == nodeCommit.weight) {
      commitments[PENDING][node][subId] = NodeCommitment(0, 0, 0, 0);
    } else {
      commitments[PENDING][node][subId].weight -= amount;
    }

    // trade;
    // todo: double check that deposit is actually in account
    // (1) check that cash exists
    // (2) check that cash is the only asset
  }

  function _checkRotateBlocks() internal {
    uint64 pendingTimestamp = timestamps[PENDING];
    // has been exeucting for 5 mins, push to finalized
    if (pendingTimestamp + 5 minutes < block.timestamp && pendingTimestamp != 0) {
      // set finalized epoch timestamp back to 0
      timestamps[PENDING] = 0;

      (FINALIZED, PENDING, COLLECTING) = (PENDING, COLLECTING, FINALIZED);
    } 

    uint64 collectingTimestamp = timestamps[COLLECTING];
    // if first value, record first timestamp
    if (collectingTimestamp + 5 minutes < block.timestamp || collectingTimestamp == 0) {
      timestamps[COLLECTING] = SafeCast.toUint64(block.timestamp);
    }
  }
}
