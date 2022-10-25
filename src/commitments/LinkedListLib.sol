//SPDX-License-Identifier: ISC

pragma solidity ^0.8.13;

import "./CommitmentLinkedList.sol";

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
    uint64 nodeId
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
        uint16 pointer = list.head;

        while (true) {
          CommitmentLinkedList.VolEntity memory current = list.entities[pointer];
          if (current.vol > vol) {
            break;
          } else {
            pointer = current.next;

            // we reach the end!
            if (pointer == 0) {
              isEnd = true;
              break;
            }
          }
        }

        if (pointer != 0) {
          prev = list.entities[pointer].prev;
          next = list.entities[pointer].next;
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
