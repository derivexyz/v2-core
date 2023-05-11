// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "lyra-utils/encoding/OptionEncoding.sol";
import "openzeppelin/utils/math/SafeCast.sol";

import {IAsset} from "src/interfaces/IAsset.sol";
import {IManager} from "src/interfaces/IManager.sol";
import {IAccounts} from "src/interfaces/IAccounts.sol";
import {IBasicManager} from "src/interfaces/IBasicManager.sol";

import {IPerpAsset} from "src/interfaces/IPerpAsset.sol";
import {IOption} from "src/interfaces/IOption.sol";

import {ISingleExpiryPortfolio} from "src/interfaces/ISingleExpiryPortfolio.sol";

import {StrikeGrouping} from "src/libraries/StrikeGrouping.sol";

/**
 * @title BasicManagerPortfolioLib
 * @notice util functions for BasicManagerPortfolio structs
 */
library BasicManagerPortfolioLib {
  function addPerpToPortfolio(IBasicManager.BasicManagerSubAccount memory subAccount, IAsset perp, int balance)
    internal
    pure
  {
    // find the subAccount that has the same underlying id
    subAccount.perp = IPerpAsset(address(perp));
    subAccount.perpPosition = balance;
  }

  /**
   * @dev return if an expiry exists in an array of expiry holdings
   * @param expiryHoldings All holdings
   * @param expiryToFind  strike to find
   * @param arrayLen # of strikes already active
   * @return index index of the found element. 0 if not found
   * @return found true if found
   */
  function findExpiryInArray(IBasicManager.ExpiryHolding[] memory expiryHoldings, uint expiryToFind, uint arrayLen)
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
}
