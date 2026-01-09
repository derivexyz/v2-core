// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "./PMRM_2.sol";

/**
 * @title PMRM_2_1
 * @author Derive
 * @notice Upgrade to PMRM_2 adding per-account risk library overrides
 */
contract PMRM_2_1 is PMRM_2 {
  /// @notice Optional per-account risk lib override (0-address => use default `lib`).
  mapping(uint => IPMRMLib_2) internal accountLibOverride; // accountId => lib

  bytes[48] private __gap;

  //////////////////
  // Lib Override //
  //////////////////

  /// @notice Set (or clear) a per-account risk lib override.
  /// @dev Owner can set any lib; guardian may only clear back to default (set to 0).
  /// Anyone can clear it during liquidation.
  function setLibOverride(uint accountId, IPMRMLib_2 _libOverride) external {
    bool allowed = msg.sender == owner();
    if (address(_libOverride) == address(0)) {
      // Allow guardian to clear overridden lib at any time, or anyone if account is in liquidation
      allowed = allowed || msg.sender == guardian || liquidation.isAuctionLive(accountId);
    }
    require(allowed, PM21_CannotChangeLib());
    accountLibOverride[accountId] = _libOverride;
    emit LibOverrideUpdated(accountId, _libOverride);
  }

  /// @notice Returns the lib used for this account (override if set, otherwise default `lib`).
  function getAccountLib(uint accountId) public view returns (IPMRMLib_2) {
    IPMRMLib_2 libOverride = accountLibOverride[accountId];
    return address(libOverride) == address(0) ? lib : libOverride;
  }

  ////////////
  // Events //
  ////////////
  event LibOverrideUpdated(uint indexed accountId, IPMRMLib_2 libOverride);

  ////////////
  // Errors //
  ////////////
  error PM21_CannotChangeLib();

  /////////////////////////////////////////////
  // Overwritten functions - refer to PMRM_2 //
  /////////////////////////////////////////////
  function _assessRisk(address caller, uint accountId, ISubAccounts.AssetBalance[] memory assetBalances)
    internal
    view
    override
  {
    IPMRM_2.Portfolio memory portfolio = _arrangePortfolio(accountId, assetBalances);
    IPMRMLib_2 accountLib = getAccountLib(accountId);

    if (trustedRiskAssessor[caller]) {
      // If the caller is a trusted risk assessor, only use the basis contingency scenarios (3 scenarios)
      (int atmMM,,) = accountLib.getMarginAndMarkToMarket(portfolio, false, accountLib.getBasisContingencyScenarios());
      if (atmMM >= 0) return;
    } else {
      // If the caller is not a trusted risk assessor, use all the margin scenarios
      (int postIM,,) = accountLib.getMarginAndMarkToMarket(portfolio, true, marginScenarios);
      if (postIM >= 0) return;
    }
    revert PMRM_2_InsufficientMargin();
  }

  /**
   * @notice Arrange portfolio into cash + arranged
   *         array of [strikes][calls / puts / forwards].
   * @param assets Array of balances for given asset and subId.
   * @return portfolio Cash + option holdings.
   */
  function _arrangePortfolio(uint accountId, ISubAccounts.AssetBalance[] memory assets)
    internal
    view
    override
    returns (IPMRM_2.Portfolio memory portfolio)
  {
    (uint seenExpiries, uint collateralCount, PortfolioExpiryData[] memory expiryCount) =
      _countExpiriesAndAssets(assets);

    portfolio.expiries = new ExpiryHoldings[](seenExpiries);
    portfolio.collaterals = new CollateralHoldings[](collateralCount);
    (portfolio.spotPrice, portfolio.minConfidence) = spotFeed.getSpot();
    (portfolio.stablePrice,) = stableFeed.getSpot();

    _initialiseExpiries(portfolio, expiryCount);
    _arrangeAssets(accountId, portfolio, assets, collateralCount, expiryCount);

    if (portfolio.perpPosition != 0) {
      (uint perpPrice, uint perpConfidence) = perp.getPerpPrice();
      portfolio.perpPrice = perpPrice;
      portfolio.minConfidence = Math.min(portfolio.minConfidence, perpConfidence);
    }

    portfolio = getAccountLib(accountId).addPrecomputes(portfolio);

    return portfolio;
  }

  /**
   * @notice Get the initial margin or maintenance margin of an account
   * @dev if the returned value is negative, it means the account is under margin requirement
   */
  function getMargin(uint accountId, bool isInitial) external view override returns (int) {
    IPMRM_2.Portfolio memory portfolio = _arrangePortfolio(accountId, subAccounts.getAccountBalances(accountId));
    (int margin,,) = getAccountLib(accountId).getMarginAndMarkToMarket(portfolio, isInitial, marginScenarios);
    return margin;
  }

  /**
   * @notice Get the initial margin, mtm and worst scenario or maintenance margin of an account
   */
  function getMarginAndMtM(uint accountId, bool isInitial)
    external
    view
    override
    returns (int margin, int mtm, uint worstScenario)
  {
    IPMRM_2.Portfolio memory portfolio = _arrangePortfolio(accountId, subAccounts.getAccountBalances(accountId));
    return getAccountLib(accountId).getMarginAndMarkToMarket(portfolio, isInitial, marginScenarios);
  }

  /**
   * @notice Get margin level and mark to market of an account
   */
  function getMarginAndMarkToMarket(uint accountId, bool isInitial, uint scenarioId)
    external
    view
    override
    returns (int margin, int mtm)
  {
    IPMRM_2.Portfolio memory portfolio = _arrangePortfolio(accountId, subAccounts.getAccountBalances(accountId));
    IPMRM_2.Scenario[] memory scenarios = new IPMRM_2.Scenario[](1);

    scenarios[0] = marginScenarios[scenarioId];

    (margin, mtm,) = getAccountLib(accountId).getMarginAndMarkToMarket(portfolio, isInitial, scenarios);
    return (margin, mtm);
  }

  function getScenarioPnL(uint accountId, uint scenarioId) external view override returns (int scenarioMtM) {
    IPMRM_2.Portfolio memory portfolio = _arrangePortfolio(accountId, subAccounts.getAccountBalances(accountId));
    if (scenarioId == marginScenarios.length) {
      // basis scenario
      return getAccountLib(accountId).getScenarioPnL(portfolio, marginScenarios[0]);
    }
    IPMRM_2.Scenario memory scenario = marginScenarios[scenarioId];
    return getAccountLib(accountId).getScenarioPnL(portfolio, scenario);
  }
}
