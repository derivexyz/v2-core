// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/interfaces/AccountStructs.sol";
import "src/risk-managers/PCRM.sol";
import "src/libraries/IntLib.sol";

/**
 * @title PCRMSorting
 * @author Lyra
 * @notice util functions for sorting PCRM account holdings
 */

library PCRMSorting {

  ///////////////
  // Filtering //
  ///////////////

  function filterForwards(PCRM.ExpiryHolding[] memory expiryHoldings) 
    internal
    pure 
  {
    for (uint i; i < expiryHoldings.length; i++) {
      for (uint j; j < expiryHoldings[i].strikes.length; j++) {
        (int newCalls, int newPuts, int newForwards) = _filterForwards(
          expiryHoldings[i].strikes[j].calls,
          expiryHoldings[i].strikes[j].puts,
          expiryHoldings[i].strikes[j].forwards
        );

        expiryHoldings[i].strikes[j].calls = newCalls;
        expiryHoldings[i].strikes[j].puts = newPuts;
        expiryHoldings[i].strikes[j].forwards = newForwards;
      }
    }
  }

  function _filterForwards(int calls, int puts, int forwards) 
    internal
    pure
    returns (int newCalls, int newPuts, int newForwards) {
    // if calls and puts have opposing signs, forwards are present
    int additionalFwds;
    if (calls * puts < 0) {
      int fwdSign = (calls > 0) ? int(1) : -1;
      additionalFwds = int(IntLib.absMin(calls, puts)) * fwdSign;
    }

    newCalls = calls - newForwards;
    newPuts = puts + newForwards;
    newForwards = forwards + additionalFwds;
  }

  /////////////
  // Sorting //
  /////////////

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

  function addUniqueStrike(PCRM.ExpiryHolding[] memory expiryHoldings, uint expiryIndex, uint newStrike, uint arrayLen)
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

  // todo [Josh]: change to binary search

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


  function findInArray(PCRM.StrikeHolding[] memory strikeHoldings, uint strikeToFind, uint arrayLen) 
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
