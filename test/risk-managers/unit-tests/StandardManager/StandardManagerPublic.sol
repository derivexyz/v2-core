// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "src/risk-managers/StandardManager.sol";

contract StandardManagerPublic is StandardManager {
  constructor(ISubAccounts subAccounts_, ICashAsset cashAsset_, IDutchAuction _dutchAuction)
    StandardManager(subAccounts_, cashAsset_, _dutchAuction)
  {}

  function getMarginByBalances(ISubAccounts.AssetBalance[] memory balances, uint accountId)
    external
    view
    returns (int im, int mm, int mtm)
  {
    StandardManagerPortfolio memory portfolio = _arrangePortfolio(balances);
    (im, mtm) = _getMarginAndMarkToMarket(accountId, portfolio, true);
    (mm,) = _getMarginAndMarkToMarket(accountId, portfolio, false);
  }
}