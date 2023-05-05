// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "openzeppelin/utils/math/SafeCast.sol";
import "lyra-utils/decimals/DecimalMath.sol";
import "lyra-utils/encoding/OptionEncoding.sol";

import "src/libraries/StrikeGrouping.sol";
import {ISingleExpiryPortfolio} from "src/interfaces/ISingleExpiryPortfolio.sol";
import {IAccounts} from "src/interfaces/IAccounts.sol";

abstract contract SingleExpiryPortfolio is ISingleExpiryPortfolio {
  /**
   * @notice Adds option to portfolio holdings.
   * @dev This option arrangement is only additive, as portfolios are reconstructed for every trade
   * @param portfolio current portfolio of account
   * @param asset option asset to be added
   * @return addedStrikeIndex index of existing or added strike struct
   */
  function _addOption(Portfolio memory portfolio, IAccounts.AssetBalance memory asset)
    internal
    pure
    returns (uint addedStrikeIndex)
  {
    // decode subId
    (uint expiry, uint strikePrice, bool isCall) = OptionEncoding.fromSubId(SafeCast.toUint96(asset.subId));

    // assume expiry = 0 means this is the first strike.
    if (portfolio.expiry == 0) {
      portfolio.expiry = expiry;
    }

    if (portfolio.expiry != expiry) {
      revert SEP_OnlySingleExpiryPerAccount();
    }

    // add strike in-memory to portfolio
    (addedStrikeIndex, portfolio.numStrikesHeld) =
      StrikeGrouping.findOrAddStrike(portfolio.strikes, strikePrice, portfolio.numStrikesHeld);

    // add call or put balance
    if (isCall) {
      portfolio.strikes[addedStrikeIndex].calls += asset.balance;
    } else {
      portfolio.strikes[addedStrikeIndex].puts += asset.balance;
    }

    // return the index of the strike which was just modified
    return addedStrikeIndex;
  }
}