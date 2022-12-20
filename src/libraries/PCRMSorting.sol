// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/interfaces/AccountStructs.sol";
import "src/risk-managers/PCRM.sol";
import "src/libraries/IntLib.sol";
import "forge-std/console2.sol";

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
    PCRM.StrikeHolding[] memory strikes;
    for (uint i; i < expiryHoldings.length; i++) {
      strikes = expiryHoldings[i].strikes;
      for (uint j; j < strikes.length; j++) {
        (
          strikes[j].calls,
          strikes[j].puts,
          strikes[j].forwards
        ) = filterForwardsForStrike(
          strikes[j].calls,
          strikes[j].puts,
          strikes[j].forwards
        );
      }
    }
  }

  function filterForwardsForStrike(int calls, int puts, int forwards) 
    internal
    pure
    returns (int newCalls, int newPuts, int newForwards) {
    // if calls and puts have opposing signs, forwards are present
    int additionalFwds;
    if (calls * puts < 0) {
      int fwdSign = (calls > 0) ? int(1) : -1;
      additionalFwds = int(IntLib.absMin(calls, puts)) * fwdSign;
    }

    newCalls = calls - additionalFwds;
    newPuts = puts + additionalFwds;
    newForwards = forwards + additionalFwds;
  }

  /////////////
  // Sorting //
  /////////////

  function addUniqueExpiry(
    PCRM.ExpiryHolding[] memory expiryHoldings, 
    uint newExpiry, 
    uint arrayLen, 
    uint maxStrikes
  )
    internal
    pure
    returns (uint, uint)
  {

    // check if expiry exists
    (uint expiryIndex, bool found) = findInArray(expiryHoldings, newExpiry, arrayLen);

    // return index if found or add new entry
    if (found == false) {
      expiryIndex = arrayLen;
      unchecked {
        expiryHoldings[arrayLen++] = PCRM.ExpiryHolding({
          expiry: newExpiry,
          numStrikesHeld: 0,
          strikes: new PCRM.StrikeHolding[](maxStrikes)
        });
      }
    }
    return (expiryIndex, arrayLen);
  }

  function addUniqueStrike(
    PCRM.ExpiryHolding memory expiryHolding, 
    uint newStrike 
)
    internal
    view
    returns (uint, uint)
  {
    (uint strikeIndex, bool found) = findInArray(
      expiryHolding.strikes, newStrike, expiryHolding.numStrikesHeld
    );
    if (found == false) {
      strikeIndex = expiryHolding.numStrikesHeld++;
      unchecked {
        expiryHolding.strikes[strikeIndex] = PCRM.StrikeHolding({
          strike: newStrike,
          calls: 0,
          puts: 0,
          forwards: 0 
        });
      }
    }
    return (strikeIndex, expiryHolding.numStrikesHeld);
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
