// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/interfaces/IManager.sol";
import "src/interfaces/IAccounts.sol";
import "src/interfaces/ISpotFeeds.sol";
import "src/interfaces/IDutchAuction.sol";
import "src/interfaces/ICashAsset.sol";
import "src/assets/Option.sol";
import "src/libraries/OptionEncoding.sol";
import "src/libraries/PCRMGrouping.sol";
import "src/libraries/BlackScholesV2.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/math/SignedMath.sol";
import "synthetix/Owned.sol";
import "synthetix/SignedDecimalMath.sol";
import "synthetix/DecimalMath.sol";

import "forge-std/console2.sol";
/**
 * @title PartialCollateralRiskManager
 * @author Lyra
 * @notice Risk Manager that controls transfer and margin requirements
 */

contract PCRM is IManager, Owned {
  using SignedDecimalMath for int;
  using DecimalMath for uint;

  /**
   * INITIAL: margin required for trade to pass
   * MAINTENANCE: margin required to prevent liquidation
   */
  enum MarginType {
    INITIAL,
    MAINTENANCE
  }

  struct ExpiryHolding {
    /// timestamp of expiry for all strike holdings
    uint expiry;
    /// # of strikes with active balances
    uint numStrikesHeld;
    /// array of strike holding details
    StrikeHolding[] strikes;
  }

  struct StrikeHolding {
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

  /// @dev asset used in all settlements and denominates margin
  IAccounts public immutable account;

  /// @dev spotFeeds that determine staleness and return prices
  ISpotFeeds public spotFeeds;

  /// @dev asset used in all settlements and denominates margin
  ICashAsset public immutable cashAsset;

  /// @dev reserved option asset
  Option public immutable option;

  /// @dev dutch auction contract used to auction liquidatable accounts
  IDutchAuction public immutable dutchAuction;

  /// @dev max number of expiries allowed to be held in one account
  uint public constant MAX_EXPIRIES = 8;

  /// @dev max number of strikes per expiry allowed to be held in one account
  uint public constant MAX_STRIKES = 16;

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

  constructor(address account_, address spotFeeds_, address cashAsset_, address option_, address auction_) Owned() {
    account = IAccounts(account_);
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
  function handleAdjustment(uint accountId, address, AccountStructs.AssetDelta[] memory, bytes memory)
    public
    view
    override
  {
    // todo [Josh]: whitelist check

    // PCRM calculations
    ExpiryHolding[] memory expiries = _groupOptions(account.getAccountBalances(accountId));
    int cashAmount = _getCashAmount(accountId);
    _calcMargin(expiries, cashAmount, MarginType.INITIAL);
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
   * @param _shocks Spot / vol / risk-free-rate shocks
   * @param _discounts Global discounting of assets.
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
   * @return expiryHoldings Sorted array of option holdings used to recompute new auction bounds
   * @return cash Amount of cash held or borrowed in account
   */
  function executeBid(uint accountId, uint liquidatorId, uint portion, uint cashAmount)
    external
    onlyAuction
    returns (int postExecutionInitialMargin, ExpiryHolding[] memory, int cash)
  {
    // todo [Cameron / Dom]: this would be only dutch auction contract
  }

  /////////////////
  // Margin Math //
  /////////////////

  /**
   * @notice Calculate the initial or maintenance margin of account.
   *         A negative value means the account is X amount over the required margin.
   * @param expiries Sorted array of option holdings.
   * @param marginType Initial or maintenance margin.
   * @return margin Amount by which account is over or under the required margin.
   */

  // todo [Josh]: add RV related add-ons
  function _calcMargin(ExpiryHolding[] memory expiries, int cashAmount, MarginType marginType)
    internal
    view
    returns (int margin)
  {
    // get shock amounts
    uint spotUp;
    uint spotDown;
    uint spot = spotFeeds.getSpot(1); // todo [Josh]: create feedId setting method
    int staticDiscount;
    console2.log("passed 1");
    if (marginType == MarginType.INITIAL) {
      spotUp = spot.multiplyDecimal(shocks.spotUpInitial);
      spotDown = spot.multiplyDecimal(shocks.spotDownInitial);
      staticDiscount = SafeCast.toInt256(discounts.initialStaticDiscount);
    } else {
      spotUp = spot.multiplyDecimal(shocks.spotUpMaintenance);
      spotDown = spot.multiplyDecimal(shocks.spotDownMaintenance);
      staticDiscount = SafeCast.toInt256(discounts.maintenanceStaticDiscount);
    }
    // todo [Josh]: add actual vol shocks

    console2.log("passed 2");

    // discount option value
    for (uint i; i < expiries.length; i++) {
      int expiryMargin;
      ExpiryHolding memory expiry = expiries[i];
      int timeToExpiry = SafeCast.toInt256(expiry.expiry) - SafeCast.toInt256(block.timestamp);
      if (timeToExpiry > 0) {
        console2.log("passed 2.1");
        expiryMargin = _calcLiveExpiryValue(expiry, spotUp, spotDown, 1e18);
        expiryMargin =
          (expiryMargin > 0) ? expiryMargin * _getExpiryDiscount(staticDiscount, timeToExpiry) : expiryMargin;
      } else {
        expiryMargin += _calcSettledExpiryValue(expiry);
      }

      // aggregate margin
      margin += expiryMargin;
    }

    // add cash
    margin += cashAmount;
  }

  /**
   * @notice Calculate the settled value of option holdings in a specific expiry.
   * @param expiry All option holdings within an expiry.
   * @return expiryValue Value of assets or debt of settled options.
   */
  function _calcSettledExpiryValue(ExpiryHolding memory expiry) internal pure returns (int expiryValue) {
    uint settlementPrice = 1000e18; // todo: [Josh] integrate settlement feed
    for (uint i; i < expiry.strikes.length; i++) {
      StrikeHolding memory strike = expiry.strikes[i];
      int pnl = SafeCast.toInt256(settlementPrice) - SafeCast.toInt256(strike.strike);

      // calculate proceeds for forwards / calls / puts
      expiryValue += strike.calls.multiplyDecimal(SignedMath.max(pnl, 0));
      expiryValue += strike.puts.multiplyDecimal(SignedMath.min(-pnl, 0));
      expiryValue += strike.forwards.multiplyDecimal(pnl);
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
  function _calcLiveExpiryValue(ExpiryHolding memory expiry, uint spotUp, uint spotDown, uint shockedVol)
    internal
    view
    returns (int expiryValue)
  {
    int spotUpValue;
    int spotDownValue;

    uint timeToExpiry = expiry.expiry - block.timestamp;

    for (uint i; i < expiry.strikes.length; i++) {
      console2.log("passed 3");
      spotUpValue += _calcLiveStrikeValue(
        expiry.strikes[i], true, SafeCast.toInt256(spotUp), SafeCast.toInt256(spotDown), shockedVol, timeToExpiry
      );

      spotDownValue += _calcLiveStrikeValue(
        expiry.strikes[i], false, SafeCast.toInt256(spotUp), SafeCast.toInt256(spotDown), shockedVol, timeToExpiry
      );
    }

    // return the worst of two scenarios
    return SignedMath.min(spotUpValue, spotDownValue);
  }

  /**
   * @notice Calculate the discounted value of live option holdings in a specific strike.
   * @param strikeHoldings All option holdings of the same strike.
   * @param isCurrentScenarioUp Whether the current scenario is spot up or down.
   * @param spotUp Spot shocked up based on initial or maintenance margin params.
   * @param spotDown Spot shocked down based on initial or maintenance margin params.
   * @param shockedVol Vol shocked up based on initial or maintenance margin params.
   * @param timeToExpiry Seconds till expiry.
   * @return strikeValue Value of assets or debt of options of a given strike.
   */

  function _calcLiveStrikeValue(
    StrikeHolding memory strikeHoldings,
    bool isCurrentScenarioUp,
    int spotUp,
    int spotDown,
    uint shockedVol,
    uint timeToExpiry
  ) internal view returns (int strikeValue) {
    // calculate both spot up and down payoffs
    int markedDownCallValue = spotDown - SafeCast.toInt256(strikeHoldings.strike);
    int markedDownPutValue = SafeCast.toInt256(strikeHoldings.strike) - spotUp;

    // Calculate forward value.
    strikeValue += (isCurrentScenarioUp)
      ? strikeHoldings.forwards.multiplyDecimal(-markedDownPutValue)
      : strikeHoldings.forwards.multiplyDecimal(markedDownCallValue);

    // Get BlackSchole price.
    (uint callValue, uint putValue) = (0, 0);
    if (strikeHoldings.calls != 0 || strikeHoldings.puts != 0) {
      (callValue, putValue) = BlackScholesV2.prices(
        BlackScholesV2.BlackScholesInputs({
          timeToExpirySec: timeToExpiry,
          volatilityDecimal: shockedVol,
          spotDecimal: (isCurrentScenarioUp) ? SafeCast.toUint256(spotUp) : SafeCast.toUint256(spotDown),
          strikePriceDecimal: strikeHoldings.strike,
          rateDecimal: 1e16 // todo [Josh]: replace with proper RFR
        })
      );
    }

    // Calculate call value.
    strikeValue += (strikeHoldings.calls >= 0)
      ? strikeHoldings.calls.multiplyDecimal(SignedMath.max(markedDownCallValue, 0))
      : strikeHoldings.calls.multiplyDecimal(SafeCast.toInt256(callValue));

    // Calculate put value.
    strikeValue += (strikeHoldings.puts >= 0)
      ? strikeHoldings.puts.multiplyDecimal(SignedMath.max(markedDownPutValue, 0))
      : strikeHoldings.puts.multiplyDecimal(SafeCast.toInt256(putValue));
  }

  function _getExpiryDiscount(int staticDiscount, int timeToExpiry) internal view returns (int expiryDiscount) {
    int tau = timeToExpiry * 10e18 / SECONDS_PER_YEAR;
    int exponent = SafeCast.toInt256(FixedPointMathLib.exp(-tau.multiplyDecimal(SafeCast.toInt256(shocks.rfr))));

    return (staticDiscount * exponent);
  }

  //////////
  // Util //
  //////////

  /**
   * @notice Group all option holdings into an array of
   *         [expiries][strikes][calls / puts / forwards].
   * @param assets Array of balances for given asset and subId.
   * @return expiryHoldings Grouped array of option holdings.
   */

  function _groupOptions(AccountStructs.AssetBalance[] memory assets)
    internal
    view
    returns (ExpiryHolding[] memory expiryHoldings)
  {
    uint numExpiriesHeld;
    uint expiryIndex;
    uint strikeIndex;
    expiryHoldings = new PCRM.ExpiryHolding[](
      MAX_EXPIRIES > assets.length ? assets.length : MAX_EXPIRIES
    );

    ExpiryHolding memory currentExpiry;
    StrikeHolding memory currentStrike;
    AccountStructs.AssetBalance memory currentAsset;
    // create sorted [expiries][strikes] 2D array
    for (uint i; i < assets.length; ++i) {
      currentAsset = assets[i];
      if (address(currentAsset.asset) == address(option)) {
        // decode subId
        (uint expiry, uint strike, bool isCall) = OptionEncoding.fromSubId(SafeCast.toUint96(currentAsset.subId));

        // add new expiry or strike to holdings if unique
        (expiryIndex, numExpiriesHeld) =
          PCRMGrouping.findOrAddExpiry(expiryHoldings, expiry, numExpiriesHeld, MAX_STRIKES);
        currentExpiry = expiryHoldings[expiryIndex];

        (strikeIndex, currentExpiry.numStrikesHeld) =
          PCRMGrouping.findOrAddStrike(currentExpiry.strikes, strike, currentExpiry.numStrikesHeld);

        // add call or put balance
        currentStrike = currentExpiry.strikes[strikeIndex];
        if (isCall) {
          currentStrike.calls += currentAsset.balance;
        } else {
          currentStrike.puts += currentAsset.balance;
        }

        // if both calls / puts present, pair-off into forwards
        if (currentStrike.calls != 0 && currentStrike.puts != 0) {
          PCRMGrouping.updateForwards(currentStrike);
        }
      }
    }
  }

  /**
   * @notice Returns the cash amount in account.
   *         Meant to be called before getInitial/MaintenanceMargin()
   * @dev Separated getter for cash to reduce stack-too-deep errors / bloating margin logic
   * @param accountId accountId of user.
   * @return cashAmount Positive or negative amount of cash in given account.
   */
  function _getCashAmount(uint accountId) internal view returns (int cashAmount) {
    return account.getBalance(accountId, IAsset(address(cashAsset)), 0);
  }

  //////////
  // View //
  //////////

  /**
   * @notice Group all option holdings of an account into an array of
   *         [expiries][strikes][calls / puts / forwards].
   * @param accountId ID of account to sort.
   * @return expiryHoldings Grouped array of option holdings.
   */
  function getGroupedOptions(uint accountId) external view returns (ExpiryHolding[] memory expiryHoldings) {
    return _groupOptions(account.getAccountBalances(accountId));
  }

  /**
   * @notice Calculate the initial margin of account.
   *         A negative value means the account is X amount over the required margin.
   * @param expiries Sorted array of option holdings.
   * @return margin Amount by which account is over or under the required margin.
   */
  // todo [Josh]: public view function to get margin values directly through accountId
  function getInitialMargin(ExpiryHolding[] memory expiries, int cashAmount) external view returns (int margin) {
    return _calcMargin(expiries, cashAmount, MarginType.INITIAL);
  }

  /**
   * @notice Calculate the maintenance margin of account.
   *         A negative value means the account is X amount over the required margin.
   * @param expiries Sorted array of option holdings.
   * @return margin Amount by which account is over or under the required margin.
   */
  function getMaintenanceMargin(ExpiryHolding[] memory expiries, int cashAmount) external view returns (int margin) {
    return _calcMargin(expiries, cashAmount, MarginType.MAINTENANCE);
  }

  ////////////
  // Errors //
  ////////////

  error PCRM_OnlyAuction(address sender, address auction);
}
