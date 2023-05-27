// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "src/risk-managers/PMRM.sol";

contract PMRMPublic is PMRM {
  constructor(
    ISubAccounts subAccounts_,
    ICashAsset cashAsset_,
    IOption option_,
    IPerpAsset perp_,
    IOptionPricing optionPricing_,
    IWrappedERC20Asset baseAsset_,
    Feeds memory feeds_
  ) PMRM(subAccounts_, cashAsset_, option_, perp_, optionPricing_, baseAsset_, feeds_) {}

  function arrangePortfolioByBalances(ISubAccounts.AssetBalance[] memory assets)
    external
    view
    returns (IPMRM.Portfolio memory portfolio)
  {
    return _arrangePortfolio(0, assets, true);
  }

  function getMarginByBalances(ISubAccounts.AssetBalance[] memory assets, bool isInitial) external view returns (int) {
    IPMRM.Portfolio memory portfolio = _arrangePortfolio(0, assets, true);
    (int im,) = _getMarginAndMarkToMarket(portfolio, isInitial, marginScenarios, true);
    return im;
  }
}
