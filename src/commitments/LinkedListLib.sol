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

// struct Participants {
//   uint64 nodeId;
//   uint64 weight;
// }

library LinkedListLib {
  function addParticipantToLinkedList(
    CommitmentLinkedList.SortedList storage list,
    uint16 vol,
    uint64 weight,
    uint64 nodeId,
    bool isBid
  ) internal {
    CommitmentLinkedList.VolEntity storage volEntity = list.entities[vol];
    if (!volEntity.initialized) {
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
      volEntity.prev = prev;
      volEntity.next = next;
      volEntity.initialized = true;
      volEntity.participants.push(CommitmentLinkedList.Participants(nodeId, weight));

      // update the prev and next node
      if (prev != 0) list.entities[prev].next = vol;
      if (next != 0) list.entities[next].prev = vol;

      list.length += 1;
    } else {
      // already have this vol node.
      // decide if increase weight or push to participant array.
      // right now, just push to the array.
      volEntity.participants.push(CommitmentLinkedList.Participants(nodeId, weight));
    }
  }
}
