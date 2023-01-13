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
import "src/libraries/Black76.sol";
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

  /// @dev max number of strikes per expiry allowed to be held in one account
  uint public constant MAX_STRIKES = 128;

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
    ExpiryHolding memory expiry = _groupOptions(account.getAccountBalances(accountId));
    int cashAmount = _getCashAmount(accountId);

    // todo [Josh]: might make more semantic case to not incldue "cashAmount" in here.
    _calcMargin(expiry, cashAmount, MarginType.INITIAL);
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
   * @param expiry Account option holdings.
   * @param marginType Initial or maintenance margin.
   * @return margin Amount by which account is over or under the required margin.
   */

  // todo [Josh]: add RV related add-ons
  function _calcMargin(ExpiryHolding memory expiry, int cashAmount, MarginType marginType)
    internal
    view
    returns (int margin)
  {
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
    int timeToExpiry = expiry.expiry.toInt256() - block.timestamp.toInt256();
    if (timeToExpiry > 0) {
      margin = _calcLiveExpiryValue(expiry, spotUp, spotDown, 1e18);
      if (margin > 0) {
        margin.multiplyDecimal(_getExpiryDiscount(staticDiscount, timeToExpiry));
      }
    } else {
      margin = _calcSettledExpiryValue(expiry);
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
  function _calcLiveExpiryValue(ExpiryHolding memory expiry, uint128 spotUp, uint128 spotDown, uint128 shockedVol)
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
    uint128 spotUp,
    uint128 spotDown,
    uint128 shockedVol,
    uint64 timeToExpiry
  ) internal pure returns (int strikeValue) {
    // Calculate both spot up and down payoffs.
    int markedDownCallValue = uint(spotDown).toInt256() - strikeHoldings.strike.toInt256();
    int markedDownPutValue = strikeHoldings.strike.toInt256() - uint(spotUp).toInt256();

    // Add forward value.
    strikeValue += (isCurrentScenarioUp)
      ? strikeHoldings.forwards.multiplyDecimal(-markedDownPutValue)
      : strikeHoldings.forwards.multiplyDecimal(markedDownCallValue);

    // Get BlackSchole price.
    (uint callValue, uint putValue) = (0, 0);
    if (strikeHoldings.calls != 0 || strikeHoldings.puts != 0) {
      (callValue, putValue) = Black76.prices(
        Black76.Black76Inputs({
          timeToExpirySec: timeToExpiry,
          volatility: shockedVol,
          fwdPrice: (isCurrentScenarioUp) ? spotUp : spotDown,
          strikePrice: strikeHoldings.strike.toUint128(),
          discount: uint64(1e18)
        })
      );
    }

    // Add call value.
    strikeValue += (strikeHoldings.calls >= 0)
      ? strikeHoldings.calls.multiplyDecimal(SignedMath.max(markedDownCallValue, 0))
      : strikeHoldings.calls.multiplyDecimal(callValue.toInt256());

    // Add put value.
    strikeValue += (strikeHoldings.puts >= 0)
      ? strikeHoldings.puts.multiplyDecimal(SignedMath.max(markedDownPutValue, 0))
      : strikeHoldings.puts.multiplyDecimal(putValue.toInt256());
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
   * @notice Group all option holdings into an array of
   *         [expiries][strikes][calls / puts / forwards].
   * @param assets Array of balances for given asset and subId.
   * @return expiryHolding Grouped array of option holdings.
   */

  function _groupOptions(AccountStructs.AssetBalance[] memory assets)
    internal
    view
    returns (ExpiryHolding memory expiryHolding)
  {
    uint strikeIndex;
    expiryHolding.strikes = new PCRM.StrikeHolding[](
      MAX_STRIKES > assets.length ? assets.length : MAX_STRIKES
    );

    StrikeHolding memory currentStrike;
    AccountStructs.AssetBalance memory currentAsset;
    // create sorted [expiries][strikes] 2D array
    for (uint i; i < assets.length; ++i) {
      currentAsset = assets[i];
      if (address(currentAsset.asset) == address(option)) {
        // decode subId
        (uint expiry, uint strikePrice, bool isCall) = OptionEncoding.fromSubId(SafeCast.toUint96(currentAsset.subId));

        if (expiryHolding.expiry == 0) {
          expiryHolding.expiry = expiry;
        } else if (expiryHolding.expiry != expiry) {
          revert(""); // todo: add error
        }

        (strikeIndex, expiryHolding.numStrikesHeld) =
          PCRMGrouping.findOrAddStrike(expiryHolding.strikes, strikePrice, expiryHolding.numStrikesHeld);

        // add call or put balance
        currentStrike = expiryHolding.strikes[strikeIndex];
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

      // todo [Josh]: should we block any other stray assets?
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
   *         [strikes][calls / puts / forwards].
   * @param accountId ID of account to sort.
   * @return expiryHolding Grouped array of option holdings.
   */
  function getGroupedOptions(uint accountId) external view returns (ExpiryHolding memory expiryHolding) {
    return _groupOptions(account.getAccountBalances(accountId));
  }

  /**
   * @notice Calculate the initial margin of account.
   *         A negative value means the account is X amount over the required margin.
   * @param expiry Sorted array of option holdings.
   * @return margin Amount by which account is over or under the required margin.
   */
  // todo [Josh]: public view function to get margin values directly through accountId
  function getInitialMargin(ExpiryHolding memory expiry, int cashAmount) external view returns (int margin) {
    return _calcMargin(expiry, cashAmount, MarginType.INITIAL);
  }

  /**
   * @notice Calculate the maintenance margin of account.
   *         A negative value means the account is X amount over the required margin.
   * @param expiry Sorted array of option holdings.
   * @return margin Amount by which account is over or under the required margin.
   */
  function getMaintenanceMargin(ExpiryHolding memory expiry, int cashAmount) external view returns (int margin) {
    return _calcMargin(expiry, cashAmount, MarginType.MAINTENANCE);
  }

  ////////////
  // Errors //
  ////////////

  error PCRM_OnlyAuction(address sender, address auction);
}
