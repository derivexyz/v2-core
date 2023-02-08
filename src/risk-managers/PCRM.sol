// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/math/SignedMath.sol";

import "src/interfaces/IManager.sol";
import "src/interfaces/IAccounts.sol";
import "src/interfaces/ISpotFeeds.sol";
import "src/interfaces/IDutchAuction.sol";
import "src/interfaces/ICashAsset.sol";
import "src/interfaces/IOption.sol";
import "src/interfaces/ISecurityModule.sol";

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

  /// @dev dutch auction contract used to auction liquidatable accounts
  IDutchAuction public immutable dutchAuction;

  /// @dev max number of strikes per expiry allowed to be held in one account
  uint public constant MAX_STRIKES = 64;

  /// @dev account id that receive OI fee
  uint public feeRecipientAcc;

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
      revert PCRM_OnlyAuction();
    }
    _;
  }

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(IAccounts accounts_, ISpotFeeds spotFeeds_, ICashAsset cashAsset_, IOption option_, address auction_)
    BaseManager(accounts_, spotFeeds_, cashAsset_, option_)
    Owned()
  {
    dutchAuction = IDutchAuction(auction_);
  }

  ///////////////////
  // Account Hooks //
  ///////////////////

  /**
   * @notice Ensures asset is valid and initial margin is met.
   * @param accountId Account for which to check trade.
   */
  function handleAdjustment(uint accountId, uint tradeId, address, AssetDelta[] calldata assetDeltas, bytes memory)
    public
    override
  {
    // todo [Josh]: whitelist check

    _chargeOIFee(accountId, feeRecipientAcc, tradeId, assetDeltas);

    // PCRM calculations
    Portfolio memory portfolio = _arrangePortfolio(accounts.getAccountBalances(accountId));

    // check initial margin
    _checkMargin(portfolio, MarginType.INITIAL);
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

  /**
   * @dev Governance determined account to receive OI fee
   * @param _newAcc account id
   */
  function setFeeRecipient(uint _newAcc) external onlyOwner {
    // this line will revert if the owner tries to set an invalid account
    accounts.ownerOf(_newAcc);

    feeRecipientAcc = _newAcc;
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
   * @param liquidatorFee Cash amount liquidator will be paying the security module
   */
  function executeBid(uint accountId, uint liquidatorId, uint portion, uint cashAmount, uint liquidatorFee)
    external
    onlyAuction
  {
    if (portion > DecimalMath.UNIT) revert PCRM_InvalidBidPortion();
    AccountStructs.AssetBalance[] memory assetBalances = accounts.getAccountBalances(accountId);

    // transfer liquidated account's asset to liquidator
    for (uint i; i < assetBalances.length; i++) {
      _symmetricManagerAdjustment(
        accountId,
        liquidatorId,
        assetBalances[i].asset,
        uint96(assetBalances[i].subId),
        assetBalances[i].balance.multiplyDecimal(int(portion))
      );
    }

    // transfer cash (bid amount) to liquidated account
    _symmetricManagerAdjustment(liquidatorId, accountId, cashAsset, 0, int(cashAmount));

    // transfer fee to security module
    _symmetricManagerAdjustment(liquidatorId, feeRecipientAcc, cashAsset, 0, int(liquidatorFee));

    // check liquidator's account status
    Portfolio memory portfolio = _arrangePortfolio(accounts.getAccountBalances(liquidatorId));
    _checkMargin(portfolio, MarginType.INITIAL);
  }

  /////////////////
  // Margin Math //
  /////////////////

  /**
   * @notice revert if a portfolio is under margin
   * @param portfolio Account portfolio
   * @param marginType Initial or maintenance margin.
   */
  function _checkMargin(Portfolio memory portfolio, MarginType marginType) internal view {
    int margin = _calcMargin(portfolio, marginType);
    if (margin < 0) revert PCRM_MarginRequirementNotMet(margin);
  }

  /**
   * @notice Calculate the initial or maintenance margin of account.
   *         A positive value means the account is X amount over the required margin.
   * @param portfolio Account portfolio.
   * @param marginType Initial or maintenance margin.
   * @return margin Amount by which account is over or under the required margin.
   */
  function _calcMargin(Portfolio memory portfolio, MarginType marginType) internal view returns (int margin) {
    // todo [Josh]: add RV related add-ons

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
   * @notice Calculate the settled value of option portfolio.
   * @param portfolio All option portfolio
   * @return expiryValue Value of assets or debt of settled options.
   */
  function _calcSettledExpiryValue(Portfolio memory portfolio) internal view returns (int expiryValue) {
    uint settlementPrice = option.settlementPrices(portfolio.expiry);
    for (uint i; i < portfolio.strikes.length; i++) {
      Strike memory strike = portfolio.strikes[i];
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
   * @notice Calculate the discounted value of live option portfolio in a specific expiry.
   * @param portfolio All option portfolio within an expiry.
   * @param spotUp Spot shocked up based on initial or maintenance margin params.
   * @param spotDown Spot shocked down based on initial or maintenance margin params.
   * @param shockedVol Vol shocked up based on initial or maintenance margin params.
   * @return expiryValue Value of assets or debt of options in a given expiry.
   */
  function _calcLiveExpiryValue(Portfolio memory portfolio, uint128 spotUp, uint128 spotDown, uint128 shockedVol)
    internal
    view
    returns (int expiryValue)
  {
    int spotUpValue;
    int spotDownValue;

    uint64 timeToExpiry = (portfolio.expiry - block.timestamp).toUint64();

    for (uint i; i < portfolio.strikes.length; i++) {
      spotUpValue += _calcLiveStrikeValue(portfolio.strikes[i], true, spotUp, spotDown, shockedVol, timeToExpiry);

      spotDownValue += _calcLiveStrikeValue(portfolio.strikes[i], false, spotUp, spotDown, shockedVol, timeToExpiry);
    }

    // return the worst of two scenarios
    return SignedMath.min(spotUpValue, spotDownValue);
  }

  /**
   * @notice Calculate the discounted value of live option portfolio in a specific strike.
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

    // Get BlackScholes price.
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

  function _arrangePortfolio(AssetBalance[] memory assets) internal view returns (Portfolio memory portfolio) {
    portfolio.strikes = new PCRM.Strike[](
      MAX_STRIKES > assets.length ? assets.length : MAX_STRIKES
    );

    AssetBalance memory currentAsset;
    uint strikeIndex;
    for (uint i; i < assets.length; ++i) {
      currentAsset = assets[i];
      if (address(currentAsset.asset) == address(option)) {
        // add option balance to portfolio in-memory
        strikeIndex = _arrangeOption(portfolio, currentAsset);

        // if possible, combine calls and puts into forwards
        PCRMGrouping.updateForwards(portfolio.strikes[strikeIndex]);
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
   * @param portfolio Cash + arranged option portfolio.
   * @return margin Amount by which account is over or under the required margin.
   */
  // todo [Josh]: public view function to get margin values directly through accountId
  function getInitialMargin(Portfolio memory portfolio) external view returns (int margin) {
    return _calcMargin(portfolio, MarginType.INITIAL);
  }

  /**
   * @notice Calculate the maintenance margin of account.
   *         A negative value means the account is X amount over the required margin.
   * @param portfolio Cash + arranged option portfolio.
   * @return margin Amount by which account is over or under the required margin.
   */
  function getMaintenanceMargin(Portfolio memory portfolio) external view returns (int margin) {
    return _calcMargin(portfolio, MarginType.MAINTENANCE);
  }

  ////////////
  // Errors //
  ////////////

  error PCRM_OnlyAuction();

  error PCRM_InvalidBidPortion();

  error PCRM_MarginRequirementNotMet(int initMargin);
}
