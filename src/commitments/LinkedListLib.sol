//SPDX-License-Identifier: ISC

pragma solidity ^0.8.13;

import "./CommitmentLinkedList.sol";
import "forge-std/console2.sol";

// struct SortedList {
//   mapping(uint16 => VolNode) nodes;
//   uint16 length;
//   uint16 head;
//   uint16 end;
// }

// struct VolNode {
//   uint16 prev;
//   uint16 next;
//   uint16 vol;
//   address[] stakers;
// }

// struct Staker {
//   uint64 stakerId;
//   uint64 weight;
// }

library LinkedListLib {
  error NotInVolArray();

  /// @param weight: standard size to commit
  /// @param collateral amount USDC locked
  /// @return index in the staker list
  function addStakerToLinkedList(
    CommitmentLinkedList.SortedList storage list,
    uint16 vol,
    uint64 weight, // todo: can probably pack all to single word
    uint128 collateral,
    uint64 stakerId,
    uint64 epoch
  ) internal returns (uint) {
    CommitmentLinkedList.VolNode storage volNode = list.nodes[vol];
    if (!volNode.initialized || volNode.epoch != epoch) {
      // find the position to insert the node
      // find the first one larger than "vol"
      uint16 prev;
      uint16 next;

      // list is empty
      if (list.head == 0) {
        list.head = vol;
        list.end = vol;
      } else {
        bool isEnd = false;
        uint16 currentVol = list.head;

        while (true) {
          if (currentVol > vol) {
            break;
          } else {
            CommitmentLinkedList.VolNode memory current = list.nodes[currentVol];
            currentVol = current.next;

            // we reach the end!
            if (currentVol == 0) {
              isEnd = true;
              break;
            }
          }
        }
        // if (isBid) console2.log("first bigger than me", currentVol);

        if (currentVol != 0) {
          prev = list.nodes[currentVol].prev;
          next = currentVol;
          if (prev == 0) {
            list.head = vol;
          }
        } else if (isEnd) {
          // vol is higher than everyone
          prev = list.end;
          list.end = vol;
        } else {
          // vol is lower than everyone
          next = list.head;
          list.head = vol;
        }
      }

      // update prev and next
      volNode.epoch = epoch;
      volNode.prev = prev;
      volNode.next = next;
      volNode.initialized = true;
      volNode.stakes.push(CommitmentLinkedList.Stake(stakerId, weight, collateral));

      // update the prev and next node
      if (prev != 0) list.nodes[prev].next = vol;
      if (next != 0) list.nodes[next].prev = vol;

      list.length += 1;
    } else {
      // already have this vol node.
      // decide if increase weight or push to staker array.
      // right now, just push to the array.
      volNode.stakes.push(CommitmentLinkedList.Stake(stakerId, weight, collateral));
    }

    volNode.totalWeight += weight;

    // always added to the last index
    return (volNode.stakes.length - 1);
  }

  function removeWeightFromVolList(CommitmentLinkedList.SortedList storage list, uint16 vol, uint64 weight)
    internal
    returns (CommitmentLinkedList.Stake[] memory, uint length)
  {
    CommitmentLinkedList.VolNode storage volNode = list.nodes[vol];
    if (!volNode.initialized) revert NotInVolArray();

    uint64 newTotalWeight = volNode.totalWeight - weight;

    volNode.totalWeight = newTotalWeight;

    CommitmentLinkedList.Stake[] memory stakers = new CommitmentLinkedList.Stake[](volNode.stakes.length);

    if (newTotalWeight == 0) {
      // remove node from the linked list
      (uint16 cachePrev, uint16 cacheNext) = (volNode.prev, volNode.next);
      if (cachePrev != 0) {
        list.nodes[cachePrev].next = cacheNext;
      } else {
        list.head = cacheNext;
      }
      if (cacheNext != 0) {
        list.nodes[cacheNext].prev = cachePrev;
      } else {
        list.end = cachePrev;
      }

      // return all stakers
      stakers = volNode.stakes;
      length = stakers.length;

      delete volNode.stakes;
    } else {
      uint64 sum;
      for (uint i = 0; i < volNode.stakes.length; i++) {
        length += 1;
        CommitmentLinkedList.Stake memory staker = volNode.stakes[i];
        if (sum + staker.weight > weight) {
          uint64 amountExecuted = weight - sum;

          uint128 collatToUnlock = staker.collateral * amountExecuted / staker.weight;

          // the payout is old collateral - newCollat
          stakers[i] = CommitmentLinkedList.Stake(staker.stakerId, amountExecuted, collatToUnlock);

          // update state
          volNode.stakes[i].weight -= amountExecuted;
          volNode.stakes[i].collateral -= collatToUnlock;

          break;
        } else {
          stakers[i] = staker;

          volNode.stakes[i].weight = 0;
          volNode.stakes[i].collateral = 0;
        }
      }
    }

    return (stakers, length);
  }

  function removeStakerWeight(
    CommitmentLinkedList.SortedList storage list,
    uint16 vol,
    uint64 weightToReduce,
    uint64 stakerIndx
  ) internal {
    CommitmentLinkedList.VolNode storage volNode = list.nodes[vol];

    uint64 stakerWeight = volNode.stakes[stakerIndx].weight;

    // do not change the array length, otherwise we will mess up the index
    uint stakerNewWeight = stakerWeight - weightToReduce;

    if (stakerNewWeight == 0) {
      delete volNode.stakes[stakerIndx];
    } else {
      volNode.stakes[stakerIndx].weight -= weightToReduce;
    }

    // reduce totalWeight and check if we need to keep this vol
    volNode.totalWeight -= weightToReduce;

    if (volNode.totalWeight != 0) return;

    // if totalWeigth = 0: remove from linked list
    (uint16 cachePrev, uint16 cacheNext) = (volNode.prev, volNode.next);
    if (cachePrev != 0) {
      list.nodes[cachePrev].next = cacheNext;
    } else {
      list.head = cacheNext;
    }
    if (cacheNext != 0) {
      list.nodes[cacheNext].prev = cachePrev;
    } else {
      list.end = cachePrev;
    }
  }

  function clearList(CommitmentLinkedList.SortedList storage list) internal {
    list.head = 0;
    list.end = 0;
    list.length = 0;
  }
}
