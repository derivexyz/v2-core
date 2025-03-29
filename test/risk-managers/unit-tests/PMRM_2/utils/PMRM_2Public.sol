// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "../../../../../src/risk-managers/PMRM_2.sol";

contract PMRM_2Public is PMRM_2 {
  constructor() {}

  function arrangePortfolioByBalances(ISubAccounts.AssetBalance[] memory assets)
    external
    view
    returns (IPMRM_2.Portfolio memory portfolio)
  {
    return _arrangePortfolio(0, assets);
  }

  function getMarginByBalances(ISubAccounts.AssetBalance[] memory assets, bool isInitial) external view returns (int) {
    IPMRM_2.Portfolio memory portfolio = _arrangePortfolio(0, assets);
    (int im,,) = lib.getMarginAndMarkToMarket(portfolio, isInitial, marginScenarios);
    return im;
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

  function findInArrayPub(ExpiryHoldings[] memory expiryData, uint expiryToFind, uint arrayLen)
    external
    pure
    returns (uint)
  {
    uint index = findInArray(expiryData, expiryToFind, arrayLen);
    return index;
  }

  function getMarginAndMarkToMarketPub(
    IPMRM_2.Portfolio memory portfolio,
    bool isInitial,
    IPMRM_2.Scenario[] memory scenarios
  ) external view returns (int, int, uint) {
    return lib.getMarginAndMarkToMarket(portfolio, isInitial, scenarios);
  }
}
