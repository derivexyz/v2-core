// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/math/SignedMath.sol";

import "lyra-utils/decimals/DecimalMath.sol";
import "lyra-utils/decimals/SignedDecimalMath.sol";
import "lyra-utils/math/IntLib.sol";
import "lyra-utils/ownership/Owned.sol";

import "src/interfaces/IManager.sol";
import "src/interfaces/IAccounts.sol";
import "src/interfaces/ICashAsset.sol";
import "src/interfaces/IPerpAsset.sol";
import "src/interfaces/IBaseManager.sol";
import "src/interfaces/IOption.sol";
import "src/interfaces/IChainlinkSpotFeed.sol";
import "src/interfaces/ISimpleManager.sol";

import "./BaseManager.sol";

import "forge-std/console2.sol";

/**
 * @title SimpleManager
 * @author Lyra
 * @notice Risk Manager that margin in perp, cash and option in isolation.
 */

contract SimpleManager is ISimpleManager, BaseManager {
  using SignedDecimalMath for int;
  using DecimalMath for uint;
  using SafeCast for uint;
  using IntLib for int;

  ///////////////
  // Variables //
  ///////////////

  uint constant MAX_STRIKES = 64;

  /// @dev Perp asset address
  IPerpAsset public immutable perp;

  /// @dev Future feed oracle to get future price for an expiry
  IChainlinkSpotFeed public immutable feed;

  /// @dev Maintenance margin requirement: min percentage of notional value to avoid liquidation
  uint public maintenanceMarginRequirement = 0.03e18;

  /// @dev Initial margin requirement: min percentage of notional value to modify a position
  uint public initialMarginRequirement = 0.05e18;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(IAccounts accounts_, ICashAsset cashAsset_, IOption option_, IPerpAsset perp_, IChainlinkSpotFeed feed_)
    BaseManager(accounts_, feed_, feed_, cashAsset_, option_)
  {
    perp = perp_;
    feed = feed_;
  }

  ////////////////////////
  //    Admin-Only     //
  ///////////////////////

  /**
   * @notice Set the maintenance margin requirement
   * @param _mmRequirement new maintenance margin requirement
   * @param _imRequirement new initial margin requirement
   */
  function setPerpMarginRequirements(uint _mmRequirement, uint _imRequirement) external onlyOwner {
    if (_mmRequirement > _imRequirement) revert PM_InvalidMarginRequirement();
    if (_mmRequirement == 0 || _mmRequirement >= 1e18) revert PM_InvalidMarginRequirement();
    if (_imRequirement >= 1e18) revert PM_InvalidMarginRequirement();

    maintenanceMarginRequirement = _mmRequirement;
    initialMarginRequirement = _imRequirement;

    emit MarginRequirementsSet(_mmRequirement, _imRequirement);
  }

  ////////////////////////
  //   Account Hooks   //
  ////////////////////////

  /**
   * @notice Ensures asset is valid and Max Loss margin is met.
   * @param accountId Account for which to check trade.
   */
  function handleAdjustment(uint accountId, uint, /*tradeId*/ address, AssetDelta[] calldata assetDeltas, bytes memory)
    public
    view
    override
  {
    // check the call is from Accounts

    // check assets are only cash and perp
    for (uint i = 0; i < assetDeltas.length; i++) {
      if (assetDeltas[i].asset != cashAsset && assetDeltas[i].asset != perp && assetDeltas[i].asset != option) {
        revert PM_UnsupportedAsset();
      }
    }

    int indexPrice = feed.getSpot().toInt256();

    int cashBalance = accounts.getBalance(accountId, cashAsset, 0);

    int perpMargin = _getPerpMargin(accountId, indexPrice);

    if (cashBalance < perpMargin) {
      revert PM_PortfolioBelowMargin(accountId, perpMargin);
    }
  }

  /**
   * @notice get the margin required for the perp position
   * @param accountId Account Id for which to check
   */
  function _getPerpMargin(uint accountId, int indexPrice) internal view returns (int) {
    uint notional = accounts.getBalance(accountId, perp, 0).multiplyDecimal(indexPrice).abs();
    int marginRequired = notional.multiplyDecimal(initialMarginRequirement).toInt256();
    return marginRequired;
  }

  function _getOptionMargin(uint accountId, int indexPrice) internal view returns (int) {
    // compute net call

    //
  }

  /**
   * @notice Ensures new manager is valid.
   * @param newManager IManager to change account to.
   */
  function handleManagerChange(uint, /*accountId*/ IManager newManager) external view {
    if (!whitelistedManager[address(newManager)]) {
      revert PM_NotWhitelistManager();
    }
  }

  /**
   * @notice to settle an account, clear PNL and funding in the perp contract and pay out cash
   */
  function settleFullAccount(uint accountId) external {
    perp.updateFundingRate();
    perp.applyFundingOnAccount(accountId);

    // settle perp
    int netCash = perp.settleRealizedPNLAndFunding(accountId);

    // todo: settle option

    cashAsset.updateSettledCash(netCash);

    // update user cash amount
    accounts.managerAdjustment(AccountStructs.AssetAdjustment(accountId, cashAsset, 0, netCash, bytes32(0)));

    emit AccountSettled(accountId, netCash);
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
    returns (IBaseManager.Portfolio memory portfolio)
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
        if (currentAsset.balance < 0) revert("Negative Cash");

        portfolio.cash = currentAsset.balance;
      } else if (currentAsset.asset == perp) {
        portfolio.perp = currentAsset.balance;
      } else {
        revert("WHAT");
      }
    }
  }

  /**
   * @notice Calculate the required margin of the account using the Max Loss method.
   *         A positive value means the account is X amount over the required margin.
   * @param portfolio Account portfolio.
   * @return margin Amount by which account is over or under the required margin.
   */
  function _calcMaxLossMargin(IBaseManager.Portfolio memory portfolio) internal view returns (int margin) {
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
      // todo: should use isolated margin
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

  //////////
  // View //
  //////////
}
