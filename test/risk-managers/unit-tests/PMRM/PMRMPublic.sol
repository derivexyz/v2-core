// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "src/risk-managers/PMRM.sol";

contract PMRMPublic is PMRM {
  constructor(
    IAccounts accounts_,
    ICashAsset cashAsset_,
    IOption option_,
    IPerpAsset perp_,
    IOptionPricing optionPricing_,
    WrappedERC20Asset baseAsset_,
    Feeds memory feeds_
  ) PMRM(accounts_, cashAsset_, option_, perp_, optionPricing_, baseAsset_, feeds_) {}

  function arrangePortfolioByBalances(IAccounts.AssetBalance[] memory assets)
    external
    view
    returns (IPMRM.Portfolio memory portfolio)
  {
    return _arrangePortfolio(0, assets, true);
  }

  function getMarginByBalances(IAccounts.AssetBalance[] memory assets, bool isInitial) external view returns (int) {
    IPMRM.Portfolio memory portfolio = _arrangePortfolio(0, assets, true);
    (int im,) = _getMarginAndMarkToMarket(portfolio, isInitial, marginScenarios, true);
    return im;
  }
}