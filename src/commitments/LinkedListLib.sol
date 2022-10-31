//SPDX-License-Identifier: ISC

pragma solidity ^0.8.13;

import "./CommitmentLinkedList.sol";
import "forge-std/console2.sol";

// struct SortedList {
//   mapping(uint16 => VolInfo) entities;
//   uint16 length;
//   uint16 head;
//   uint16 end;
// }

// struct VolInfo {
//   uint16 prev;
//   uint16 next;
//   uint16 vol;
//   address[] stakers;
// }

// struct Staker {
//   uint64 nodeId;
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
    uint64 nodeId,
    uint64 epoch
  ) internal returns (uint) {
    CommitmentLinkedList.VolInfo storage volEntity = list.entities[vol];
    if (!volEntity.initialized || volEntity.epoch != epoch) {
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
            CommitmentLinkedList.VolInfo memory current = list.entities[currentVol];
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
          prev = list.entities[currentVol].prev;
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
      volEntity.epoch = epoch;
      volEntity.prev = prev;
      volEntity.next = next;
      volEntity.initialized = true;
      volEntity.stakers.push(CommitmentLinkedList.Staker(nodeId, weight, collateral));

      // update the prev and next node
      if (prev != 0) list.entities[prev].next = vol;
      if (next != 0) list.entities[next].prev = vol;

      list.length += 1;
    } else {
      // already have this vol node.
      // decide if increase weight or push to staker array.
      // right now, just push to the array.
      volEntity.stakers.push(CommitmentLinkedList.Staker(nodeId, weight, collateral));
    }

    volEntity.totalWeight += weight;

    // always added to the last index
    return (volEntity.stakers.length - 1);
  }

  function removeWeightFromVolList(CommitmentLinkedList.SortedList storage list, uint16 vol, uint64 weight)
    internal
    returns (CommitmentLinkedList.Staker[] memory, uint length)
  {
    CommitmentLinkedList.VolInfo storage volEntity = list.entities[vol];
    if (!volEntity.initialized) revert NotInVolArray();

    uint64 newTotalWeight = volEntity.totalWeight - weight;

    volEntity.totalWeight = newTotalWeight;

    CommitmentLinkedList.Staker[] memory stakers = new CommitmentLinkedList.Staker[](volEntity.stakers.length);

    if (newTotalWeight == 0) {
      // remove node from the linked list
      (uint16 cachePrev, uint16 cacheNext) = (volEntity.prev, volEntity.next);
      if (cachePrev != 0) {
        list.entities[cachePrev].next = cacheNext;
      } else {
        list.head = cacheNext;
      }
      if (cacheNext != 0) {
        list.entities[cacheNext].prev = cachePrev;
      } else {
        list.end = cachePrev;
      }

      // return all stakers
      stakers = volEntity.stakers;
      length = stakers.length;

      delete volEntity.stakers;
    } else {
      uint64 sum;
      for (uint i = 0; i < volEntity.stakers.length; i++) {
        length += 1;
        CommitmentLinkedList.Staker memory staker = volEntity.stakers[i];
        if (sum + staker.weight > weight) {
          uint64 amountExecuted = weight - sum;

          uint128 collatToUnlock = staker.collateral * amountExecuted / staker.weight;

          // the payout is old collateral - newCollat
          stakers[i] = CommitmentLinkedList.Staker(staker.nodeId, amountExecuted, collatToUnlock);

          // update state
          volEntity.stakers[i].weight -= amountExecuted;
          volEntity.stakers[i].collateral -= collatToUnlock;

          break;
        } else {
          stakers[i] = staker;

          volEntity.stakers[i].weight = 0;
          volEntity.stakers[i].collateral = 0;
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
    CommitmentLinkedList.VolInfo storage volEntity = list.entities[vol];

    uint64 stakerWeight = volEntity.stakers[stakerIndx].weight;

    // do not change the array length, otherwise we will mess up the index
    uint stakerNewWeight = stakerWeight - weightToReduce;

    if (stakerNewWeight == 0) {
      delete volEntity.stakers[stakerIndx];
    } else {
      volEntity.stakers[stakerIndx].weight -= weightToReduce;
    }

    // reduce totalWeight and check if we need to keep this vol
    volEntity.totalWeight -= weightToReduce;

    if (volEntity.totalWeight != 0) return;

    // if totalWeigth = 0: remove from linked list
    (uint16 cachePrev, uint16 cacheNext) = (volEntity.prev, volEntity.next);
    if (cachePrev != 0) {
      list.entities[cachePrev].next = cacheNext;
    } else {
      list.head = cacheNext;
    }
    if (cacheNext != 0) {
      list.entities[cacheNext].prev = cachePrev;
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
