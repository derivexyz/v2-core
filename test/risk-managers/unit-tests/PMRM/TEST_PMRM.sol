import "src/risk-managers/PMRM.sol";

contract TEST_PMRM is PMRM {
  constructor(
    IAccounts accounts_,
    ICashAsset cashAsset_,
    IOption option_,
    IPerpAsset perp_,
    IForwardFeed futureFeed_,
    ISettlementFeed settlementFeed_,
    ISpotFeed spotFeed_,
    IMTMCache mtmCache_,
    IInterestRateFeed interestRateFeed_,
    IVolFeed volFeed_,
    WrappedERC20Asset baseAsset_,
    ISpotFeed stableFeed_
  )
    PMRM(
      accounts_,
      cashAsset_,
      option_,
      perp_,
      futureFeed_,
      settlementFeed_,
      spotFeed_,
      mtmCache_,
      interestRateFeed_,
      volFeed_,
      baseAsset_,
      stableFeed_
    )
  {}

  function arrangePortfolioByBalances(IAccounts.AssetBalance[] memory assets)
    external
    view
    returns (IPMRM.PMRM_Portfolio memory portfolio)
  {
    return _arrangePortfolio(0, assets, true);
  }

  function getMarginByBalances(IAccounts.AssetBalance[] memory assets, bool isInitial) external view returns (int) {
    IPMRM.PMRM_Portfolio memory portfolio = _arrangePortfolio(0, assets, true);
    int im = _getMargin(portfolio, isInitial, marginScenarios);
    return im;
  }
}
