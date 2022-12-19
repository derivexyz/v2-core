// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/interfaces/AccountStructs.sol";
import "src/risk-managers/PCRM.sol";

/**
 * @title PCRMSorting
 * @author Lyra
 * @notice util functions for sorting PCRM account holdings
 */

library PCRMSorting {

  function addUniqueExpiry(PCRM.ExpiryHolding[] memory expiryHoldings, uint newExpiry, uint arrayLen)
    internal
    pure
    returns (uint)
  {
    (uint expiryIndex, bool found) = findInArray(expiryHoldings, newExpiry, arrayLen);
    if (found == false) {
      unchecked {
        expiryHoldings[arrayLen++] = PCRM.ExpiryHolding({
          expiry: newExpiry,
          strikes: new PCRM.StrikeHolding[](0)
        });
      }
      expiryIndex = arrayLen;
    }     
  }

  function addUniqueStrike(PCRM.ExpiryHolding[] memory expiryHoldings, uint expiryIndex, uint64 newStrike, uint arrayLen)
    internal
    pure
    returns (uint)
  {
    (uint strikeIndex, bool found) = findInArray(expiryHoldings[expiryIndex].strikes, newStrike, arrayLen);
    if (found == false) {
      unchecked {
        expiryHoldings[expiryIndex].strikes[arrayLen++] = PCRM.StrikeHolding({
          strike: newStrike,
          calls: 0,
          puts: 0,
          forwards: 0 
        });
      }
      strikeIndex = arrayLen;
    }
  }

  // todo [Josh] change to binary search

  function findInArray(PCRM.ExpiryHolding[] memory expiryHoldings, uint expiryToFind, uint arrayLen) 
    internal 
    pure 
    returns (uint index, bool found) {
    unchecked {
      for (uint i; i < arrayLen; ++i) {
        if (expiryHoldings[i].expiry == expiryToFind) {
          return (i, true);
        }
      }
      return (0, false);
    }
  }


  function findInArray(PCRM.StrikeHolding[] memory strikeHoldings, uint64 strikeToFind, uint arrayLen) 
    internal 
    pure 
    returns (uint index, bool found) {
    unchecked {
      for (uint i; i < arrayLen; ++i) {
        if (strikeHoldings[i].strike == strikeToFind) {
          return (i, true);
        }
      }
      return (0, false);
    }
  }
}
