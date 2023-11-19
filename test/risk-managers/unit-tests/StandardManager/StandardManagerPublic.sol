// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "../../../../src/risk-managers/StandardManager.sol";

contract StandardManagerPublic is StandardManager {
  constructor(
    ISubAccounts subAccounts_,
    ICashAsset cashAsset_,
    IDutchAuction _dutchAuction,
    ISRMPortfolioViewer _viewer
  ) StandardManager(subAccounts_, cashAsset_, _dutchAuction, _viewer) {}

  function getMarginByBalances(ISubAccounts.AssetBalance[] memory balances, uint accountId)
    external
    view
    returns (int im, int mm, int mtm)
  {
    StandardManagerPortfolio memory portfolio = ISRMPortfolioViewer(address(viewer)).arrangeSRMPortfolio(balances);
    (im, mtm) = _getMarginAndMarkToMarket(accountId, portfolio, true);
    (mm,) = _getMarginAndMarkToMarket(accountId, portfolio, false);
  }

  function setBalances(uint accountId, ISubAccounts.AssetBalance[] memory assets) external {
    for (uint i = 0; i < assets.length; ++i) {
      subAccounts.managerAdjustment(
        ISubAccounts.AssetAdjustment({
          acc: accountId,
          asset: assets[i].asset,
          subId: assets[i].subId,
          amount: assets[i].balance,
          assetData: bytes32(0)
        })
      );
    }
  }
}
