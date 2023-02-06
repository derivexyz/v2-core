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


import "src/libraries/OptionEncoding.sol";
import "src/libraries/PCRMGrouping.sol";
import "src/libraries/Owned.sol";
import "src/libraries/SignedDecimalMath.sol";
import "src/libraries/DecimalMath.sol";
/**
 * @title MaxLossRiskManager
 * @author Lyra
 * @notice Risk Manager that controls transfer and margin requirements
 */

contract MLRM is IManager, Owned {
  using SignedDecimalMath for int;
  using DecimalMath for uint;
  using SafeCast for uint;

  ///////////////
  // Variables //
  ///////////////

  /// @dev asset used in all settlements and denominates margin
  IAccounts public immutable account;

  /// @dev spotFeeds that determine staleness and return prices
  ISpotFeeds public spotFeeds;

  /// @dev asset used in all settlements and denominates margin
  ICashAsset public immutable cashAsset;

  /// @dev reserved option asset
  Option public immutable option;

  /// @dev max number of strikes per expiry allowed to be held in one account
  uint public constant MAX_STRIKES = 64;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(address account_, address spotFeeds_, address cashAsset_, address option_) Owned() {
    account = IAccounts(account_);
    spotFeeds = ISpotFeeds(spotFeeds_);
    cashAsset = ICashAsset(cashAsset_);
    option = Option(option_);
  }

  function handleAdjustment(uint accountId, address, AccountStructs.AssetDelta[] memory, bytes memory)
    public
    view
    override
  {
    // todo [Josh]: whitelist check

    // PCRM calculations
    Portfolio memory portfolio = _arrangePortfolio(account.getAccountBalances(accountId));

    int margin = _calcMargin(portfolio);

    if (margin < 0) {
      revert MLRM_PortfolioBelowMargin(accountId, margin);
    }

  }

  function handleManagerChange(uint accountId, IManager newManager) external {
    // todo [Josh]: nextManager whitelist check
  }



  //////////
  // Util //
  //////////

  function _calcMargin(PCRM.Portfolio memory portfolio) internal view returns (int margin) {
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
    for (uint i; i < portfolio.strikes.length; i++) {
      PCRM.Strike memory currentStrike = portfolio.strikes[i];

      margin += SignedMath.max(spot - currentStrike.strike.toInt256(), 0).multiplyDecimal(currentStrike.calls);
      margin += SignedMath.max(currentStrike.strike.toInt256() - spot, 0).multiplyDecimal(currentStrike.puts);

      totalCalls += currentStrike.calls;
    }

    // add cash
    margin += portfolio.cash;

    // check if still bounded
    if (totalCalls < 0) {
      revert MLRM_PayoffUnbounded(totalCalls);
    }

  } 

  function _arrangePortfolio(AccountStructs.AssetBalance[] memory assets)
    internal
    view
    returns (PCRM.Portfolio memory portfolio)
  {
    // note: differs from PCRM._arrangePortfolio since forwards aren't filtered
    // todo: [Josh] ok that both use the same struct but one doesn't have forwards? 
    portfolio.strikes = new PCRM.Strike[](
      MAX_STRIKES > assets.length ? assets.length : MAX_STRIKES
    );

    PCRM.Strike memory currentStrike;
    AccountStructs.AssetBalance memory currentAsset;
    uint strikeIndex;
    for (uint i; i < assets.length; ++i) {
      currentAsset = assets[i];
      if (address(currentAsset.asset) == address(option)) {
        // decode subId
        (uint expiry, uint strikePrice, bool isCall) = OptionEncoding.fromSubId(SafeCast.toUint96(currentAsset.subId));

        // assume expiry = 0 means this is the first strike.
        if (portfolio.expiry == 0) {
          portfolio.expiry = expiry;
        }

        if (portfolio.expiry != expiry) {
          revert MLRM_SingleExpiryPerAccount();
        }

        (strikeIndex, portfolio.numStrikesHeld) =
          PCRMGrouping.findOrAddStrike(portfolio.strikes, strikePrice, portfolio.numStrikesHeld);

        // add call or put balance
        currentStrike = portfolio.strikes[strikeIndex];
        if (isCall) {
          currentStrike.calls += currentAsset.balance;
        } else {
          currentStrike.puts += currentAsset.balance;
        }

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

  error MLRM_SingleExpiryPerAccount();
  error MLRM_OnlyPositiveCash();
  error MLRM_UnsupportedAsset(address asset); // could be used in both PCRM/MLRM
  error MLRM_PayoffUnbounded(int totalCalls);
  error MLRM_PortfolioBelowMargin(uint accountId, int margin);
}
