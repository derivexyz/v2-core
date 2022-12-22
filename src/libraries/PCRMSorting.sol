// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/interfaces/AccountStructs.sol";
import "src/risk-managers/PCRM.sol";
import "src/libraries/IntLib.sol";
import "forge-std/console2.sol";

/**
 * @title PCRMSorting
 * @author Lyra
 * @notice util functions for sorting / filtering PCRM account holdings
 */

library PCRMSorting {
  //////////////
  // Forwards //
  //////////////

  /**
   * @notice Take in account holdings and return updated holdings with forwards
   * @dev expiryHoldings is passed as a memory reference and thus is implicitly adjusted
   * @param expiryHoldings All account option holdings. Refer to PCRM.sol
   */
  function updateForwards(PCRM.ExpiryHolding[] memory expiryHoldings) internal pure {
    PCRM.StrikeHolding[] memory strikes;
    for (uint i; i < expiryHoldings.length; i++) {
      strikes = expiryHoldings[i].strikes;
      for (uint j; j < strikes.length; j++) {
        (strikes[j].calls, strikes[j].puts, strikes[j].forwards) =
          findForwards(strikes[j].calls, strikes[j].puts, strikes[j].forwards);
      }
    }
  }

  /**
   * @notice Pairs off calls and puts of the same strike into forwards
   *         Forward = Call - Put. Positive sign counts as a Long Forward
   * @param calls # of call contracts
   * @param puts # of put contracts
   * @param forwards # of forward contracts
   * @return newCalls # of call contracts post pair-off
   * @return newPuts # of put contracts post pair-off
   * @return newForwards # of forward contracts post pair-off
   */
  function findForwards(int calls, int puts, int forwards)
    internal
    pure
    returns (int newCalls, int newPuts, int newForwards)
  {
    // if calls and puts have opposing signs, forwards are present
    if (calls * puts < 0) {
      int fwdSign = (calls > 0) ? int(1) : -1;
      int additionalFwds = int(IntLib.absMin(calls, puts)) * fwdSign;
      return (calls - additionalFwds, puts + additionalFwds, forwards + additionalFwds);
    }
    return (calls, puts, forwards);
  }

  /////////////
  // Sorting //
  /////////////

  /**
   * @notice Adds new expiry struct if not present in holdings
   * @param expiryHoldings All account option holdings. Refer to PCRM.sol
   * @param newExpiry epoch time of new expiry
   * @param arrayLen # of expiries already active
   * @param maxStrikes max # of strikes allowed per expiry
   * @return expiryIndex index of existing or added expiry struct
   * @return newArrayLen new # of expiries post addition
   */
  function addUniqueExpiry(PCRM.ExpiryHolding[] memory expiryHoldings, uint newExpiry, uint arrayLen, uint maxStrikes)
    internal
    pure
    returns (uint, uint)
  {
    // check if expiry exists
    (uint expiryIndex, bool found) = findInArray(expiryHoldings, newExpiry, arrayLen);

    // return index if found or add new entry
    if (found == false) {
      expiryIndex = arrayLen++;
      expiryHoldings[expiryIndex] =
      PCRM.ExpiryHolding({expiry: newExpiry, numStrikesHeld: 0, strikes: new PCRM.StrikeHolding[](maxStrikes)});
    }
    return (expiryIndex, arrayLen);
  }

  /**
   * @notice Adds new strike struct if not present in holdings
   * @param strikeHoldings All holdings for a given expiry. Refer to PCRM.sol
   * @param newStrike strike price
   * @param arrayLen # of strikes already active
   * @return strikeIndex index of existing or added strike struct
   * @return newArrayLen new # of strikes post addition
   */
  function addUniqueStrike(PCRM.StrikeHolding[] memory strikeHoldings, uint newStrike, uint arrayLen)
    internal
    pure
    returns (uint, uint)
  {
    // check if strike exists
    (uint strikeIndex, bool found) = findInArray(strikeHoldings, newStrike, arrayLen);

    // return index if found or add new entry
    if (found == false) {
      strikeIndex = arrayLen++;
      strikeHoldings[strikeIndex] = PCRM.StrikeHolding({strike: newStrike, calls: 0, puts: 0, forwards: 0});
    }
    return (strikeIndex, arrayLen);
  }

  // todo [Josh]: maybe change to binary search

  /**
   * @dev return if an expiry exists in an array of expiry holdings
   * @param expiryHoldings All account option holdings. Refer to PCRM.sol
   * @param expiryToFind  expiry to find
   * @param arrayLen # of expiries already active
   * @return index index of the found element. 0 if not found
   * @return found true if found
   */
  function findInArray(PCRM.ExpiryHolding[] memory expiryHoldings, uint expiryToFind, uint arrayLen)
    internal
    pure
    returns (uint index, bool found)
  {
    unchecked {
      for (uint i; i < arrayLen; ++i) {
        if (expiryHoldings[i].expiry == expiryToFind) {
          return (i, true);
        }
      }
      return (0, false);
    }
  }

  /**
   * @dev return if an expiry exists in an array of expiry holdings
   * @param strikeHoldings All holdings for a given expiry. Refer to PCRM.sol
   * @param strikeToFind  strike to find
   * @param arrayLen # of strikes already active
   * @return index index of the found element. 0 if not found
   * @return found true if found
   */
  function findInArray(PCRM.StrikeHolding[] memory strikeHoldings, uint strikeToFind, uint arrayLen)
    internal
    pure
    returns (uint index, bool found)
  {
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
