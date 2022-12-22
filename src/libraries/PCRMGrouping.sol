// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/interfaces/AccountStructs.sol";
import "src/risk-managers/PCRM.sol";
import "src/libraries/IntLib.sol";
import "forge-std/console2.sol";

/**
 * @title PCRMGrouping
 * @author Lyra
 * @notice util functions for sorting / filtering PCRM account holdings
 */

library PCRMGrouping {
  //////////////
  // Forwards //
  //////////////

  /**
   * @notice Take in account holdings and update holdings in-place with forwards
   * @dev expiryHoldings is passed as a memory reference and thus is implicitly adjusted
   * @param expiryHoldings All account option holdings. Refer to PCRM.sol
   */
  function updateForwards(PCRM.ExpiryHolding[] memory expiryHoldings) internal pure {
    PCRM.StrikeHolding[] memory strikes;
    PCRM.StrikeHolding memory currentStrike;
    for (uint i; i < expiryHoldings.length; i++) {
      strikes = expiryHoldings[i].strikes;
      for (uint j; j < strikes.length; j++) {
        currentStrike = strikes[j];
        int additionalFwds = findForwards(currentStrike.calls, currentStrike.puts);
        if (additionalFwds != 0) {
          currentStrike.calls -= additionalFwds;
          currentStrike.puts += additionalFwds;
          currentStrike.forwards += additionalFwds;
        }
      }
    }
  }

  /**
   * @notice Pairs off calls and puts of the same strike into forwards
   *         Forward = Call - Put. Positive sign counts as a Long Forward
   * @dev if not using updateForwards(), make sure to update calls and puts with additionalFwds
   * @param calls # of call contracts
   * @param puts # of put contracts
   * @return additionalFwds # of forward contracts found
   */
  function findForwards(int calls, int puts)
    internal
    pure
    returns (int additionalFwds)
  {
    // if calls and puts have opposing signs, forwards are present
    if (calls * puts < 0) {
      int fwdSign = (calls > 0) ? int(1) : -1;
      return int(IntLib.absMin(calls, puts)) * fwdSign;
    }
    return (0);
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
  function findOrAddExpiry(PCRM.ExpiryHolding[] memory expiryHoldings, uint newExpiry, uint arrayLen, uint maxStrikes)
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
  function findOrAddStrike(PCRM.StrikeHolding[] memory strikeHoldings, uint newStrike, uint arrayLen)
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
