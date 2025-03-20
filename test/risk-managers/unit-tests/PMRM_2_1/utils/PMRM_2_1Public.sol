// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "../../../../../src/risk-managers/PMRM_2_1.sol";

contract PMRM_2_1Public is PMRM_2_1 {
  constructor(
    ISubAccounts subAccounts_,
    ICashAsset cashAsset_,
    IOptionAsset option_,
    IPerpAsset perp_,
    IDutchAuction liquidation_,
    Feeds memory feeds_,
    IBasePortfolioViewer viewer_,
    IPMRMLib_2_1 lib_
  ) PMRM_2_1(subAccounts_, cashAsset_, option_, perp_, liquidation_, feeds_, viewer_, lib_) {}

  function arrangePortfolioByBalances(ISubAccounts.AssetBalance[] memory assets)
    external
    view
    returns (IPMRM_2_1.Portfolio memory portfolio)
  {
    return _arrangePortfolio(0, assets);
  }

  function getMarginByBalances(ISubAccounts.AssetBalance[] memory assets, bool isInitial) external view returns (int) {
    IPMRM_2_1.Portfolio memory portfolio = _arrangePortfolio(0, assets);
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
    IPMRM_2_1.Portfolio memory portfolio,
    bool isInitial,
    IPMRM_2_1.Scenario[] memory scenarios
  ) external view returns (int, int, uint) {
    return lib.getMarginAndMarkToMarket(portfolio, isInitial, scenarios);
  }
}
