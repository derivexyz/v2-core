// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IAsset} from "src/interfaces/IAsset.sol";
import {IManager} from "src/interfaces/IManager.sol";
import {IAccounts} from "src/interfaces/IAccounts.sol";
import {IBasicManager} from "src/interfaces/IBasicManager.sol";

import {IPerpAsset} from "src/interfaces/IPerpAsset.sol";

import {ISingleExpiryPortfolio} from "src/interfaces/ISingleExpiryPortfolio.sol";

/**
 * @title BasicManagerPortfolioLib
 * @notice util functions for BasicManagerPortfolio structs
 */
library BasicManagerPortfolioLib {
  function addPerpToPortfolio(
    IBasicManager.BasicManagerPortfolio memory portfolio,
    IAsset perp,
    uint underlyingId,
    int balance
  ) internal pure {
    // find the subAccount that has the same underlying id
    for (uint i = 0; i < portfolio.subAccounts.length; i++) {
      // found the place to insert this subAccount
      if (portfolio.subAccounts[i].underlyingId == 0) {
        portfolio.subAccounts[i].underlyingId = underlyingId;
        portfolio.subAccounts[i].perp = IPerpAsset(address(perp));
        portfolio.subAccounts[i].perpPosition = balance;
        portfolio.numSubAccounts++;
        return;
      } else if (portfolio.subAccounts[i].underlyingId == underlyingId) {
        portfolio.subAccounts[i].perp = IPerpAsset(address(perp));
        portfolio.subAccounts[i].perpPosition = balance;
        return;
      }
    }
    revert("MAX_SUB_ACCOUNTS");
  }

  function addOptionToPortfolio(
    IBasicManager.BasicManagerPortfolio memory portfolio,
    uint underlyingId,
    uint96 subId,
    int balance
  ) internal pure {
    // find the asset that has the same id
    uint index = 0;
    portfolio.subAccounts[index].numExpiries = 1;
  }

  function findOrAddExpiryHolding(
    IBasicManager.OptionPortfolioSingleExpiry[] memory expires,
    uint newExpiry,
    uint arrayLen
  ) internal pure returns (uint, uint) {
    // check if strike exists
    (uint expiryIndex, bool found) = findExpiryInArray(expires, newExpiry, arrayLen);

    // return index if found or add new entry
    if (found == false) {
      expiryIndex = arrayLen++;
      expires[expiryIndex] = IBasicManager.OptionPortfolioSingleExpiry({
        expiry: newExpiry,
        numStrikesHeld: 0,
        strikes: new ISingleExpiryPortfolio.Strike[](32)
      });
    }
    return (expiryIndex, arrayLen);
  }

  /**
   * @dev return if an expiry exists in an array of expiry holdings
   * @param expiryHoldings All holdings
   * @param expiryToFind  strike to find
   * @param arrayLen # of strikes already active
   * @return index index of the found element. 0 if not found
   * @return found true if found
   */
  function findExpiryInArray(
    IBasicManager.OptionPortfolioSingleExpiry[] memory expiryHoldings,
    uint expiryToFind,
    uint arrayLen
  ) internal pure returns (uint index, bool found) {
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
