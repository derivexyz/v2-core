// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "lyra-utils/math/IntLib.sol";

import "src/interfaces/ISingleExpiryPortfolio.sol";
/**
 * @title StrikeGrouping
 * @author Lyra
 * @notice util functions for sorting / filtering BaseManager strike holdings
 */

library StrikeGrouping {
  /////////////
  // Sorting //
  /////////////

  /**
   * @notice Adds new strike struct if not present in holdings
   * @param strikes All holdings for a given expiry. Refer to ISingleExpiryPortfolio.sol
   * @param newStrike strike price
   * @param arrayLen # of strikes already active
   * @return strikeIndex index of existing or added strike struct
   * @return newArrayLen new # of strikes post addition
   */
  function findOrAddStrike(ISingleExpiryPortfolio.Strike[] memory strikes, uint newStrike, uint arrayLen)
    internal
    pure
    returns (uint, uint)
  {
    // check if strike exists
    (uint strikeIndex, bool found) = findInArray(strikes, newStrike, arrayLen);

    // return index if found or add new entry
    if (found == false) {
      strikeIndex = arrayLen++;
      strikes[strikeIndex] = ISingleExpiryPortfolio.Strike({strike: newStrike, calls: 0, puts: 0});
    }
    return (strikeIndex, arrayLen);
  }

  /**
   * @dev return if an expiry exists in an array of expiry holdings
   * @param strikes All holdings for a given expiry. Refer to BaseManager.sol
   * @param strikeToFind  strike to find
   * @param arrayLen # of strikes already active
   * @return index index of the found element. 0 if not found
   * @return found true if found
   */
  function findInArray(ISingleExpiryPortfolio.Strike[] memory strikes, uint strikeToFind, uint arrayLen)
    internal
    pure
    returns (uint index, bool found)
  {
    unchecked {
      for (uint i; i < arrayLen; ++i) {
        if (strikes[i].strike == strikeToFind) {
          return (i, true);
        }
      }
      return (0, false);
    }
  }
}
