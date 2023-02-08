// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/math/SignedMath.sol";

import "src/interfaces/IManager.sol";
import "src/interfaces/IAccounts.sol";
import "src/interfaces/ISpotFeeds.sol";
import "src/interfaces/IDutchAuction.sol";
import "src/interfaces/ICashAsset.sol";

import "src/assets/Option.sol";
import "src/risk-managers/PCRM.sol";
import "src/assets/Option.sol";

import "./BaseManager.sol";

import "src/libraries/OptionEncoding.sol";
import "src/libraries/PCRMGrouping.sol";
import "src/libraries/SignedDecimalMath.sol";
import "src/libraries/DecimalMath.sol";
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

  constructor(IAccounts accounts_, ISpotFeeds spotFeeds_, ICashAsset cashAsset_, IOption option_)
    BaseManager(accounts_, spotFeeds_, cashAsset_, option_)
  {}

  /**
   * @notice Ensures asset is valid and Max Loss margin is met.
   * @param accountId Account for which to check trade.
   */
  function handleAdjustment(uint accountId, uint tradeId, address, AssetDelta[] calldata assetDeltas, bytes memory)
    public
    view
    override
  {
    // todo [Josh]: whitelist check
    // todo [Josh]: charge OI fee

    // PCRM calculations
    BaseManager.Portfolio memory portfolio = _arrangePortfolio(accounts.getAccountBalances(accountId));

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
  function _calcMargin(BaseManager.Portfolio memory portfolio) internal view returns (int margin) {
    // keep track to check unbounded
    int totalCalls;

    // check if expired or not
    int timeToExpiry = portfolio.expiry.toInt256() - block.timestamp.toInt256();
    int spot;
    if (timeToExpiry > 0) {
      spot = spotFeeds.getSpot(1).toInt256(); // todo [Josh]: create feedId setting method
    } else {
      spot = spotFeeds.getSpot(1).toInt256(); // todo [Josh]: need to switch over to settled price if already expired
    }

    // calculate margin
    for (uint i; i < portfolio.numStrikesHeld; i++) {
      BaseManager.Strike memory currentStrike = portfolio.strikes[i];

      margin += SignedMath.max(spot - currentStrike.strike.toInt256(), 0).multiplyDecimal(currentStrike.calls);
      margin += SignedMath.max(currentStrike.strike.toInt256() - spot, 0).multiplyDecimal(currentStrike.puts);

      totalCalls += currentStrike.calls;
    }

    // add cash
    margin += portfolio.cash;

    // check if bounded
    if (totalCalls < 0) {
      revert MLRM_PayoffUnbounded(totalCalls);
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
    portfolio.strikes = new BaseManager.Strike[](
      MAX_STRIKES > assets.length ? assets.length : MAX_STRIKES
    );

    AccountStructs.AssetBalance memory currentAsset;
    for (uint i; i < assets.length; ++i) {
      currentAsset = assets[i];
      if (address(currentAsset.asset) == address(option)) {
        _addOption(portfolio, currentAsset);
      } else if (address(currentAsset.asset) == address(cashAsset)) {
        if (currentAsset.balance >= 0) {
          revert MLRM_OnlyPositiveCash();
        }
        portfolio.cash = currentAsset.balance;
      } else {
        revert MLRM_UnsupportedAsset(address(currentAsset.asset));
      }
    }
  }

  ////////////
  // Errors //
  ////////////

  error MLRM_OnlyPositiveCash();
  error MLRM_UnsupportedAsset(address asset); // could be used in both PCRM/MLRM
  error MLRM_PayoffUnbounded(int totalCalls);
  error MLRM_PortfolioBelowMargin(uint accountId, int margin);
}
