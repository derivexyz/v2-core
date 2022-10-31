//SPDX-License-Identifier: ISC

pragma solidity ^0.8.13;

import "./CommitmentLinkedList.sol";
import "forge-std/console2.sol";

// struct SortedList {
//   mapping(uint16 => VolEntity) entities;
//   uint16 length;
//   uint16 head;
//   uint16 end;
// }

// struct VolEntity {
//   uint16 prev;
//   uint16 next;
//   uint16 vol;
//   address[] participants;
// }

// struct Participant {
//   uint64 nodeId;
//   uint64 weight;
// }

library LinkedListLib {
  error NotInVolArray();

  /// @param weight: standard size to commit
  /// @param collateral amount USDC locked
  /// @return index in the participant list
  function addParticipantToLinkedList(
    CommitmentLinkedList.SortedList storage list,
    uint16 vol,
    uint64 weight, // todo: can probably pack all to single word
    uint128 collateral,
    uint64 nodeId,
    uint64 epoch
  ) internal returns (uint) {
    CommitmentLinkedList.VolEntity storage volEntity = list.entities[vol];
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
            CommitmentLinkedList.VolEntity memory current = list.entities[currentVol];
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
        // if (isBid) console2.log("this round prev, next:", prev, next);
        // if (isBid) console2.log("===");
      }

      // update prev and next
      volEntity.epoch = epoch;
      volEntity.prev = prev;
      volEntity.next = next;
      volEntity.initialized = true;
      volEntity.participants.push(CommitmentLinkedList.Participant(nodeId, weight, collateral));

      // update the prev and next node
      if (prev != 0) list.entities[prev].next = vol;
      if (next != 0) list.entities[next].prev = vol;

      list.length += 1;
    } else {
      // already have this vol node.
      // decide if increase weight or push to participant array.
      // right now, just push to the array.
      volEntity.participants.push(CommitmentLinkedList.Participant(nodeId, weight, collateral));
    }

    volEntity.totalWeight += weight;

    // always added to the last index
    return (volEntity.participants.length - 1);
  }

  function removeWeightFromVolList(CommitmentLinkedList.SortedList storage list, uint16 vol, uint64 weight)
    internal
    returns (CommitmentLinkedList.Participant[] memory, uint length)
  {
    CommitmentLinkedList.VolEntity storage volEntity = list.entities[vol];
    if (!volEntity.initialized) revert NotInVolArray();

    uint64 newTotalWeight = volEntity.totalWeight - weight;

    volEntity.totalWeight = newTotalWeight;

    CommitmentLinkedList.Participant[] memory participants =
      new CommitmentLinkedList.Participant[](volEntity.participants.length);

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

      // return all participants
      participants = volEntity.participants;
      length = participants.length;

      delete volEntity.participants;
    } else {
      uint64 sum;
      for (uint i = 0; i < volEntity.participants.length; i++) {
        CommitmentLinkedList.Participant memory participant = volEntity.participants[i];
        if (sum + participant.weight > weight) {
          uint64 amountExecuted = weight - sum;

          uint128 collatToUnlock = participant.collateral * amountExecuted / participant.weight;

          // the payout is old collateral - newCollat
          participants[i] = CommitmentLinkedList.Participant(participant.nodeId, amountExecuted, collatToUnlock);

          // update state
          volEntity.participants[i].weight -= amountExecuted;
          volEntity.participants[i].collateral -= collatToUnlock;

          break;
        } else {
          participants[i] = participant;

          volEntity.participants[i].weight = 0;
          volEntity.participants[i].collateral = 0;
        }
        length += 1;
      }
    }

    return (participants, length);
  }

  function removeParticipant(CommitmentLinkedList.SortedList storage list, uint16 vol, uint64 participantIndx) internal {
    CommitmentLinkedList.VolEntity storage volEntity = list.entities[vol];

    uint64 weight = volEntity.participants[participantIndx].weight;

    // move last element to "participantIndex"
    uint totalParticipants = volEntity.participants.length;
    if (participantIndx != totalParticipants - 1) {
      volEntity.participants[participantIndx] = volEntity.participants[totalParticipants - 1];
    }

    volEntity.participants.pop();
    volEntity.totalWeight -= weight;
  }

  function clearList(CommitmentLinkedList.SortedList storage list) internal {
    list.head = 0;
    list.end = 0;
    list.length = 0;
  }
}
