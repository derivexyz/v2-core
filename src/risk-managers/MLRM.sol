// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/math/SignedMath.sol";

import "src/interfaces/IManager.sol";
import "src/interfaces/IAccounts.sol";
import "src/interfaces/IDutchAuction.sol";
import "src/interfaces/ICashAsset.sol";

import "src/assets/Option.sol";
import "src/risk-managers/PCRM.sol";
import "src/assets/Option.sol";

import "./BaseManager.sol";

import "src/libraries/OptionEncoding.sol";
import "src/libraries/StrikeGrouping.sol";
import "src/libraries/SignedDecimalMath.sol";
import "src/libraries/DecimalMath.sol";

import "forge-std/console2.sol";

/**
 * @title MaxLossRiskManager
 * @author Lyra
 * @notice Risk Manager that controls transfer and margin requirements
 */

contract MLRM is BaseManager, IManager {
  using SignedDecimalMath for int;
  using DecimalMath for uint;
  using SafeCast for uint;

  ///////////////
  // Variables //
  ///////////////

  /// @dev max number of strikes per expiry allowed to be held in one account
  uint public constant MAX_STRIKES = 64;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(
    IAccounts accounts_,
    IFutureFeed futureFeed_,
    ISettlementFeed _settlementFeed,
    ICashAsset cashAsset_,
    IOption option_
  ) BaseManager(accounts_, futureFeed_, _settlementFeed, cashAsset_, option_) {}

  /**
   * @notice Ensures asset is valid and Max Loss margin is met.
   * @param accountId Account for which to check trade.
   */
  function handleAdjustment(uint accountId, uint tradeId, address, AssetDelta[] calldata assetDeltas, bytes memory) public override {
    // todo [Josh]: whitelist check
    _chargeOIFee(accountId, tradeId, assetDeltas);

    IBaseManager.Portfolio memory portfolio = _arrangePortfolio(accounts.getAccountBalances(accountId));

    int margin = _calcMargin(portfolio);

    if (margin < 0) {
      revert MLRM_PortfolioBelowMargin(accountId, margin);
    }
  }

  /**
   * @notice Ensures new manager is valid.
   * @param accountId Account for which to check trade.
   * @param newManager IManager to change account to.
   */
  function handleManagerChange(uint accountId, IManager newManager) external {
    // todo [Josh]: nextManager whitelist check
  }

  //////////
  // Util //
  //////////

  /**
   * @notice Calculate the required margin of the account using the Max Loss method.
   *         A positive value means the account is X amount over the required margin.
   * @param portfolio Account portfolio.
   * @return margin Amount by which account is over or under the required margin.
   */
  function _calcMargin(IBaseManager.Portfolio memory portfolio) internal view returns (int margin) {
    // The portfolio payoff is evaluated at the strike price of each owned option.
    // This guarantees that the max loss of a portfolio can be found.
    bool zeroStrikeOwned;
    int netCalls;
    for (uint i; i < portfolio.numStrikesHeld; i++) {
      uint scenarioPrice = portfolio.strikes[i].strike;
      margin = SignedMath.min(_calcPayoffAtPrice(portfolio, scenarioPrice), margin);

      netCalls += portfolio.strikes[i].calls;

      if (scenarioPrice == 0) {
        zeroStrikeOwned = true;
      }
    }

    // Ensure $0 scenario is always evaluated.
    if (!zeroStrikeOwned) {
      margin = SignedMath.min(_calcPayoffAtPrice(portfolio, 0), margin);
    }

    // Add cash balance.
    margin += portfolio.cash;

    // Max loss cannot be calculated when netCalls below zero,
    // since short calls have an unbounded payoff.
    if (netCalls < 0) {
      revert MLRM_PayoffUnbounded(netCalls);
    }
  }

  /**
   * @notice Calculate the full portfolio payoff at a given settlement price.
   *         This is used in '_calcMargin()' calculated the max loss of a given portfolio.
   * @param portfolio Account portfolio.
   * @param price Assumed scenario price.
   * @return payoff Net $ profit or loss of the portfolio given a settlement price.
   */
  function _calcPayoffAtPrice(IBaseManager.Portfolio memory portfolio, uint price) internal view returns (int payoff) {
    for (uint i; i < portfolio.numStrikesHeld; i++) {
      IBaseManager.Strike memory currentStrike = portfolio.strikes[i];
      payoff += option.getSettlementValue(currentStrike.strike, currentStrike.calls, price, true);
      payoff += option.getSettlementValue(currentStrike.strike, currentStrike.puts, price, false);
    }
  }

  /**
   * @notice Arrange portfolio into cash + arranged
   *         array of [strikes][calls / puts].
   *         Unlike PCRM, the forwards are purposefully not filtered.
   * @param assets Array of balances for given asset and subId.
   * @return portfolio Cash + option holdings.
   */
  function _arrangePortfolio(AccountStructs.AssetBalance[] memory assets)
    internal
    view
    returns (Portfolio memory portfolio)
  {
    // note: differs from PCRM._arrangePortfolio since forwards aren't filtered
    // todo: [Josh] can just combine with PCRM _arrangePortfolio and remove struct
    portfolio.strikes = new IBaseManager.Strike[](
      MAX_STRIKES > assets.length ? assets.length : MAX_STRIKES
    );

    AccountStructs.AssetBalance memory currentAsset;
    for (uint i; i < assets.length; ++i) {
      currentAsset = assets[i];
      if (address(currentAsset.asset) == address(option)) {
        _addOption(portfolio, currentAsset);
      } else if (address(currentAsset.asset) == address(cashAsset)) {
        if (currentAsset.balance < 0) {
          revert MLRM_OnlyPositiveCash();
        }
        portfolio.cash = currentAsset.balance;
      } else {
        revert MLRM_UnsupportedAsset(address(currentAsset.asset));
      }
    }
  }

  //////////
  // View //
  //////////

  /**
   * @notice Get account portfolio, consisting of cash + arranged
   *         array of [strikes][calls / puts / forwards].
   * @param accountId ID of account to retrieve.
   * @return portfolio Cash + arranged option holdings.
   */
  function getPortfolio(uint accountId) external view returns (Portfolio memory portfolio) {
    return _arrangePortfolio(accounts.getAccountBalances(accountId));
  }

  /**
   * @notice Calculate the max loss margin of account.
   *         A negative value means the account is X amount over the required margin.
   * @param portfolio Cash + arranged option portfolio.
   * @return margin Amount by which account is over or under the required margin.
   */
  function getMargin(Portfolio memory portfolio) external view returns (int margin) {
    return _calcMargin(portfolio);
  }

  ////////////
  // Errors //
  ////////////

  error MLRM_OnlyPositiveCash();
  error MLRM_UnsupportedAsset(address asset); // todo [Josh]: should move to BaseManager
  error MLRM_PayoffUnbounded(int totalCalls);
  error MLRM_PortfolioBelowMargin(uint accountId, int margin);
}
