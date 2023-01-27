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

import "src/libraries/OptionEncoding.sol";
import "src/libraries/PCRMGrouping.sol";
import "src/libraries/Black76.sol";
import "src/libraries/Owned.sol";
import "src/libraries/SignedDecimalMath.sol";
import "src/libraries/DecimalMath.sol";

import "./BaseManager.sol";

import "forge-std/console2.sol";
/**
 * @title PartialCollateralRiskManager
 * @author Lyra
 * @notice Risk Manager that controls transfer and margin requirements
 */

contract PCRM is BaseManager, IManager, Owned {
  using SignedDecimalMath for int;
  using DecimalMath for uint;
  using SafeCast for uint;

  // todo [Josh]: move to interface

  /**
   * INITIAL: margin required for trade to pass
   * MAINTENANCE: margin required to prevent liquidation
   */
  enum MarginType {
    INITIAL,
    MAINTENANCE
  }

  struct Portfolio {
    /// cash amount or debt
    int cash;
    /// timestamp of expiry for all strike holdings
    uint expiry;
    /// # of strikes with active balances
    uint numStrikesHeld;
    /// array of strike holding details
    Strike[] strikes;
  }

  struct Strike {
    /// strike price of held options
    uint strike;
    /// number of calls held
    int calls;
    /// number of puts held
    int puts;
    /// number of forwards held
    int forwards;
  }

  struct Shocks {
    /// high spot value used for initial margin
    uint spotUpInitial;
    /// low spot value used for initial margin
    uint spotDownInitial;
    /// high spot value used for maintenance margin
    uint spotUpMaintenance;
    /// low spot value used for maintenance margin
    uint spotDownMaintenance;
    /// volatility shock
    uint vol;
    /// risk-free-rate shock
    uint rfr;
  }

  struct Discounts {
    /// maintenance discount applied to whole expiry
    uint maintenanceStaticDiscount;
    /// initial discount applied to whole expiry
    uint initialStaticDiscount;
  }

  ///////////////
  // Variables //
  ///////////////
  int constant SECONDS_PER_YEAR = 365 days;

  /// @dev spotFeeds that determine staleness and return prices
  ISpotFeeds public spotFeeds;

  /// @dev asset used in all settlements and denominates margin
  ICashAsset public immutable cashAsset;

  /// @dev reserved option asset
  Option public immutable option;

  /// @dev dutch auction contract used to auction liquidatable accounts
  IDutchAuction public immutable dutchAuction;

  /// @dev max number of strikes per expiry allowed to be held in one account
  uint public constant MAX_STRIKES = 64;

  Shocks public shocks;

  Discounts public discounts;

  ////////////
  // Events //
  ////////////

  ///////////////
  // Modifiers //
  ///////////////

  modifier onlyAuction() {
    if (msg.sender != address(dutchAuction)) {
      revert PCRM_OnlyAuction(msg.sender, address(dutchAuction));
    }
    _;
  }

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(address accounts_, address spotFeeds_, address cashAsset_, address option_, address auction_)
    BaseManager(IAccounts(accounts_))
    Owned()
  {
    spotFeeds = ISpotFeeds(spotFeeds_);
    cashAsset = ICashAsset(cashAsset_);
    option = Option(option_);
    dutchAuction = IDutchAuction(auction_);
  }

  ///////////////////
  // Account Hooks //
  ///////////////////

  /**
   * @notice Ensures asset is valid and initial margin is met.
   * @param accountId Account for which to check trade.
   */
  function handleAdjustment(uint accountId, uint, /*tradeId*/ address, AccountStructs.AssetDelta[] memory, bytes memory)
    public
    view
    override
  {
    // todo [Josh]: whitelist check

    // PCRM calculations
    Portfolio memory portfolio = _arrangePortfolio(accounts.getAccountBalances(accountId));

    _calcMargin(portfolio, MarginType.INITIAL);
  }

  /**
   * @notice Ensures new manager is valid.
   * @param accountId Account for which to check trade.
   * @param newManager IManager to change account to.
   */
  function handleManagerChange(uint accountId, IManager newManager) external {
    // todo [Josh]: nextManager whitelist check
  }

  ///////////
  // Admin //
  ///////////

  /**
   * @notice Governance determined shocks and discounts used in margin calculations.
   * @param _shocks Spot / vol / risk-free-rate shocks for inputs into BS pricing / payoffs.
   * @param _discounts discounting of portfolio value post BS pricing / payoffs.
   */
  function setParams(Shocks calldata _shocks, Discounts calldata _discounts) external onlyOwner {
    // todo [Josh]: add bounds
    shocks = _shocks;
    discounts = _discounts;
  }

  //////////////////
  // Liquidations //
  //////////////////

  /**
   * @notice Confirm account is liquidatable and puts up for dutch auction.
   * @param accountId Account for which to check trade.
   */
  function checkAndStartLiquidation(uint accountId) external {
    dutchAuction.startAuction(accountId);
    // todo [Cameron / Dom]: check that account is liquidatable / freeze account / call out to auction contract
    // todo [Cameron / Dom]: add account Id to send reward for flagging liquidation
  }

  /**
   * @notice Transfers portion of account to the liquidator.
   *         Transfers cash to the liquidated account.
   * @dev Auction contract can decide to either:
   *      - revert / process bid
   *      - continue / complete auction
   * @param accountId ID of account which is being liquidated.
   * @param liquidatorId Liquidator account ID.
   * @param portion Portion of account that is requested to be liquidated.
   * @param cashAmount Cash amount liquidator is offering for portion of account.
   * @return postExecutionInitialMargin InitialMargin of account after portion is liquidated.
   * @return Portfolio Sorted array of option holdings used to recompute new auction bounds
   * @return cash Amount of cash held or borrowed in account
   */
  function executeBid(uint accountId, uint liquidatorId, uint portion, uint cashAmount)
    external
    onlyAuction
    returns (int postExecutionInitialMargin, Portfolio[] memory, int cash)
  {
    // todo [Cameron / Dom]: this would be only dutch auction contract
  }

  /////////////////
  // Margin Math //
  /////////////////

  /**
   * @notice Calculate the initial or maintenance margin of account.
   *         A negative value means the account is X amount over the required margin.
   * @param portfolio Account holdings.
   * @param marginType Initial or maintenance margin.
   * @return margin Amount by which account is over or under the required margin.
   */

  // todo [Josh]: add RV related add-ons
  function _calcMargin(Portfolio memory portfolio, MarginType marginType) internal view returns (int margin) {
    // get shock amounts
    uint128 spotUp;
    uint128 spotDown;
    uint spot = spotFeeds.getSpot(1); // todo [Josh]: create feedId setting method
    uint staticDiscount;
    if (marginType == MarginType.INITIAL) {
      spotUp = spot.multiplyDecimal(shocks.spotUpInitial).toUint128();
      spotDown = spot.multiplyDecimal(shocks.spotDownInitial).toUint128();
      staticDiscount = discounts.initialStaticDiscount;
    } else {
      spotUp = spot.multiplyDecimal(shocks.spotUpMaintenance).toUint128();
      spotDown = spot.multiplyDecimal(shocks.spotDownMaintenance).toUint128();
      staticDiscount = discounts.maintenanceStaticDiscount;
    }
    // todo [Josh]: add actual vol shocks

    // discount option value
    int timeToExpiry = portfolio.expiry.toInt256() - block.timestamp.toInt256();
    if (timeToExpiry > 0) {
      margin = _calcLiveExpiryValue(portfolio, spotUp, spotDown, 1e18);
      if (margin > 0) {
        margin.multiplyDecimal(_getExpiryDiscount(staticDiscount, timeToExpiry));
      }
    } else {
      margin = _calcSettledExpiryValue(portfolio);
    }

    // add cash
    margin += portfolio.cash;
  }

  /**
   * @notice Calculate the settled value of option holdings in a specific expiry.
   * @param expiry All option holdings within an expiry.
   * @return expiryValue Value of assets or debt of settled options.
   */
  function _calcSettledExpiryValue(Portfolio memory expiry) internal pure returns (int expiryValue) {
    uint settlementPrice = 1000e18; // todo: [Josh] integrate settlement feed
    for (uint i; i < expiry.strikes.length; i++) {
      Strike memory strike = expiry.strikes[i];
      int pnl = settlementPrice.toInt256() - strike.strike.toInt256();

      // calculate proceeds for forwards / calls / puts
      // todo [Josh]: need to figure out the order of settlement as this may affect cash supply / borrow
      if (pnl > 0) {
        expiryValue += (strike.calls + strike.forwards).multiplyDecimal(pnl);
      } else {
        expiryValue += (strike.puts - strike.forwards).multiplyDecimal(-pnl);
      }
    }
  }

  /**
   * @notice Calculate the discounted value of live option holdings in a specific expiry.
   * @param expiry All option holdings within an expiry.
   * @param spotUp Spot shocked up based on initial or maintenance margin params.
   * @param spotDown Spot shocked down based on initial or maintenance margin params.
   * @param shockedVol Vol shocked up based on initial or maintenance margin params.
   * @return expiryValue Value of assets or debt of options in a given expiry.
   */
  function _calcLiveExpiryValue(Portfolio memory expiry, uint128 spotUp, uint128 spotDown, uint128 shockedVol)
    internal
    view
    returns (int expiryValue)
  {
    int spotUpValue;
    int spotDownValue;

    uint64 timeToExpiry = (expiry.expiry - block.timestamp).toUint64();

    for (uint i; i < expiry.strikes.length; i++) {
      spotUpValue += _calcLiveStrikeValue(expiry.strikes[i], true, spotUp, spotDown, shockedVol, timeToExpiry);

      spotDownValue += _calcLiveStrikeValue(expiry.strikes[i], false, spotUp, spotDown, shockedVol, timeToExpiry);
    }

    // return the worst of two scenarios
    return SignedMath.min(spotUpValue, spotDownValue);
  }

  /**
   * @notice Calculate the discounted value of live option holdings in a specific strike.
   * @param strikes All option holdings of the same strike.
   * @param isCurrentScenarioUp Whether the current scenario is spot up or down.
   * @param spotUp Spot shocked up based on initial or maintenance margin params.
   * @param spotDown Spot shocked down based on initial or maintenance margin params.
   * @param shockedVol Vol shocked up based on initial or maintenance margin params.
   * @param timeToExpiry Seconds till expiry.
   * @return strikeValue Value of assets or debt of options of a given strike.
   */

  function _calcLiveStrikeValue(
    Strike memory strikes,
    bool isCurrentScenarioUp,
    uint128 spotUp,
    uint128 spotDown,
    uint128 shockedVol,
    uint64 timeToExpiry
  ) internal pure returns (int strikeValue) {
    // Calculate both spot up and down payoffs.
    int markedDownCallValue = uint(spotDown).toInt256() - strikes.strike.toInt256();
    int markedDownPutValue = strikes.strike.toInt256() - uint(spotUp).toInt256();

    // Add forward value.
    strikeValue += (isCurrentScenarioUp)
      ? strikes.forwards.multiplyDecimal(-markedDownPutValue)
      : strikes.forwards.multiplyDecimal(markedDownCallValue);

    // Get BlackSchole price.
    (uint callValue, uint putValue) = (0, 0);
    if (strikes.calls != 0 || strikes.puts != 0) {
      (callValue, putValue) = Black76.prices(
        Black76.Black76Inputs({
          timeToExpirySec: timeToExpiry,
          volatility: shockedVol,
          fwdPrice: (isCurrentScenarioUp) ? spotUp : spotDown,
          strikePrice: strikes.strike.toUint128(),
          discount: uint64(1e18)
        })
      );
    }

    // Add call value.
    strikeValue += (strikes.calls >= 0)
      ? strikes.calls.multiplyDecimal(SignedMath.max(markedDownCallValue, 0))
      : strikes.calls.multiplyDecimal(callValue.toInt256());

    // Add put value.
    strikeValue += (strikes.puts >= 0)
      ? strikes.puts.multiplyDecimal(SignedMath.max(markedDownPutValue, 0))
      : strikes.puts.multiplyDecimal(putValue.toInt256());
  }

  function _getExpiryDiscount(uint staticDiscount, int timeToExpiry) internal view returns (int expiryDiscount) {
    int tau = timeToExpiry * 1e18 / SECONDS_PER_YEAR;
    int exponent = SafeCast.toInt256(FixedPointMathLib.exp(-tau.multiplyDecimal(shocks.rfr.toInt256())));

    // no need for safecast as .setParams() bounds will ensure no overflow
    return (int(staticDiscount) * exponent);
  }

  //////////
  // Util //
  //////////

  /**
   * @notice Arrange portfolio into cash + arranged
   *         array of [strikes][calls / puts / forwards].
   * @param assets Array of balances for given asset and subId.
   * @return portfolio Cash + option holdings.
   */

  // todo [Josh]: rename this
  function _arrangePortfolio(AccountStructs.AssetBalance[] memory assets)
    internal
    view
    returns (Portfolio memory portfolio)
  {
    portfolio.strikes = new PCRM.Strike[](
      MAX_STRIKES > assets.length ? assets.length : MAX_STRIKES
    );

    Strike memory currentStrike;
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
          revert PCRM_SingleExpiryPerAccount();
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

        // if possible, combine calls and puts into forwards
        PCRMGrouping.updateForwards(currentStrike);
      } else if (address(currentAsset.asset) == address(cashAsset)) {
        portfolio.cash = currentAsset.balance;
      }

      // todo [Josh]: should we block any other stray assets?
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
   * @notice Calculate the initial margin of account.
   *         A negative value means the account is X amount over the required margin.
   * @param portfolio Cash + arranged option holdings.
   * @return margin Amount by which account is over or under the required margin.
   */
  // todo [Josh]: public view function to get margin values directly through accountId
  function getInitialMargin(Portfolio memory portfolio) external view returns (int margin) {
    return _calcMargin(portfolio, MarginType.INITIAL);
  }

  /**
   * @notice Calculate the maintenance margin of account.
   *         A negative value means the account is X amount over the required margin.
   * @param portfolio Cash + arranged option holdings.
   * @return margin Amount by which account is over or under the required margin.
   */
  function getMaintenanceMargin(Portfolio memory portfolio) external view returns (int margin) {
    return _calcMargin(portfolio, MarginType.MAINTENANCE);
  }

  ////////////
  // Errors //
  ////////////

  error PCRM_OnlyAuction(address sender, address auction);

  error PCRM_SingleExpiryPerAccount();
}
