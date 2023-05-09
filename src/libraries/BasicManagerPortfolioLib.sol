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

  function addPerpToPortfolio(
    IBasicManager.BasicManagerSubAccount memory subAccount,
    IAsset perp,
    int balance
  ) internal pure {
    // find the subAccount that has the same underlying id
    subAccount.perp = IPerpAsset(address(perp));
    subAccount.perpPosition = balance;
  }

  function addOptionToPortfolio(
    IBasicManager.BasicManagerPortfolio memory portfolio,
    IAsset option,
    uint marketId,
    uint96 subId,
    int balance
  ) internal pure {
    // find the subAccount that has the same underlying id
    uint subAccountIndex;
    for (uint i = 0; i < portfolio.subAccounts.length; i++) {
      if (portfolio.subAccounts[i].marketId == 0) {
        // no such subAccount exist before
        portfolio.subAccounts[i].marketId = marketId;
        portfolio.subAccounts[i].option = IOption(address(option));
        portfolio.subAccounts[i].expiryHoldings = new IBasicManager.ExpiryHolding[](4);
        portfolio.numSubAccounts++;
        subAccountIndex = i;
      } else if (portfolio.subAccounts[i].marketId == marketId) {
        portfolio.subAccounts[i].option = IOption(address(option));
        subAccountIndex = i;
      }
    }

    // make sure expiry is in the subAccount
    // add the option into this expiry
    (uint expiry, uint strikePrice, bool isCall) = OptionEncoding.fromSubId(subId);

    (uint expiryIdx, uint newExpiryLen) = findOrAddExpiryHolding(
      portfolio.subAccounts[subAccountIndex].expiryHoldings, expiry, portfolio.subAccounts[subAccountIndex].numExpiries
    );

    portfolio.subAccounts[subAccountIndex].numExpiries = newExpiryLen;

    _addOptionToExpiry(portfolio.subAccounts[subAccountIndex].expiryHoldings[expiryIdx], strikePrice, isCall, balance);
  }

  function findOrAddExpiryHolding(IBasicManager.ExpiryHolding[] memory expires, uint newExpiry, uint arrayLen)
    internal
    pure
    returns (uint, uint)
  {
    // check if strike exists
    (uint expiryIndex, bool found) = findExpiryInArray(expires, newExpiry, arrayLen);

    // return index if found or add new entry
    if (found == false) {
      expiryIndex = arrayLen++;
      expires[expiryIndex] = IBasicManager.ExpiryHolding({
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

  /**
   * @notice Adds option to portfolio holdings.
   * @dev This option arrangement is only additive, as portfolios are reconstructed for every trade
   * @return addedStrikeIndex index of existing or added strike struct
   */
  function _addOptionToExpiry(IBasicManager.ExpiryHolding memory holdings, uint strikePrice, bool isCall, int balance)
    internal
    pure
    returns (uint addedStrikeIndex)
  {
    // add strike in-memory to portfolio
    (addedStrikeIndex, holdings.numStrikesHeld) =
      StrikeGrouping.findOrAddStrike(holdings.strikes, strikePrice, holdings.numStrikesHeld);

    // add call or put balance
    if (isCall) {
      holdings.strikes[addedStrikeIndex].calls += balance;
    } else {
      holdings.strikes[addedStrikeIndex].puts += balance;
    }

    // return the index of the strike which was just modified
    return addedStrikeIndex;
  }
}
