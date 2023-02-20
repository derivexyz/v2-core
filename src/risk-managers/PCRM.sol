// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/math/SignedMath.sol";

import "src/interfaces/IManager.sol";
import "src/interfaces/IAccounts.sol";
import "src/interfaces/IDutchAuction.sol";
import "src/interfaces/ICashAsset.sol";
import "src/interfaces/IOption.sol";
import "src/interfaces/ISecurityModule.sol";
import "src/interfaces/ISpotJumpOracle.sol";
import "src/interfaces/IPCRM.sol";

import "src/libraries/OptionEncoding.sol";
import "src/libraries/StrikeGrouping.sol";
import "src/libraries/Black76.sol";
import "src/libraries/SignedDecimalMath.sol";
import "src/libraries/DecimalMath.sol";

import "./BaseManager.sol";

import "forge-std/console2.sol";
/**
 * @title PartialCollateralRiskManager
 * @author Lyra
 * @notice Risk Manager that controls transfer and margin requirements
 */

contract PCRM is BaseManager, IManager, IPCRM {
  using SignedDecimalMath for int;
  using DecimalMath for uint;
  using SafeCast for int;
  using SafeCast for uint;

  ///////////////
  // Variables //
  ///////////////

  /// @dev dutch auction contract used to auction liquidatable accounts
  IDutchAuction public immutable dutchAuction;

  /// @dev max number of strikes per expiry allowed to be held in one account
  uint public constant MAX_STRIKES = 64;

  /// @dev spot shock parameters
  SpotShockParams public spotShockParams;

  /// @dev vol shock parameters
  VolShockParams public volShockParams;

  /// @dev discount applied to the portfolio value (less cash) as a whole
  PortfolioDiscountParams public portfolioDiscountParams;

  /// @dev finds max jump in spot during the last X days
  ISpotJumpOracle public spotJumpOracle;

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

  constructor(
    IAccounts accounts_,
    IFutureFeed futureFeed_,
    ISettlementFeed settlementFeed_,
    ICashAsset cashAsset_,
    IOption option_,
    address auction_,
    ISpotJumpOracle spotJumpOracle_
  ) BaseManager(accounts_, futureFeed_, settlementFeed_, cashAsset_, option_) {
    dutchAuction = IDutchAuction(auction_);
    spotJumpOracle = spotJumpOracle_;
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
    spotJumpOracle.updateJumps();
    // todo [Josh]: whitelist check

    // bypass the IM check if only adding cash
    if (assetDeltas.length == 1 && assetDeltas[0].asset == cashAsset && assetDeltas[0].delta >= 0) return;

    _chargeOIFee(accountId, tradeId, assetDeltas);

    // PCRM calculations
    Portfolio memory portfolio = _arrangePortfolio(accounts.getAccountBalances(accountId));

    // check initial margin
    _checkInitialMargin(portfolio);
  }

  /**
   * @notice Ensures new manager is valid.
   * @param accountId Account for which to check trade.
   * @param newManager IManager to change account to.
   */
  function handleManagerChange(uint accountId, IManager newManager) external view {
    if (!whitelistedManager[address(newManager)]) {
      revert BM_ManagerNotWhitelisted(accountId, address(newManager));
    }
  }

  ///////////
  // Admin //
  ///////////

  /**
   * @notice Governance determined shocks and discounts used in margin calculations.
   * @param _spotShock Params to determine spotShock used in BS pricing / payoffs.
   * @param _volShock Params to determine volShock used in BS pricing / payoffs.
   * @param _discount discounting of portfolio value post BS pricing / payoffs.
   */
  function setParams(
    SpotShockParams calldata _spotShock,
    VolShockParams calldata _volShock,
    PortfolioDiscountParams calldata _discount
  ) external onlyOwner {
    if (
      _spotShock.upMaintenance < DecimalMath.UNIT || _spotShock.downMaintenance > DecimalMath.UNIT
        || _spotShock.upMaintenance > _spotShock.upInitial || _spotShock.downMaintenance < _spotShock.downInitial
        || _volShock.maxVol < _volShock.minVol || _volShock.timeB <= _volShock.timeA
        || _volShock.spotJumpMultipleSlope > 100e18 || _discount.maintenance > DecimalMath.UNIT
        || _discount.initial > _discount.maintenance || _discount.riskFreeRate > 10e18
    ) {
      revert PCRM_InvalidMarginParam();
    }

    spotShockParams = _spotShock;
    volShockParams = _volShock;
    portfolioDiscountParams = _discount;
  }

  /**
   * @notice Governance determined spotJumpOracle contract for determining vol / spot add_ons.
   * @param spotJumpOracle_ Contract that finds max jump in spot during the last X days.
   */
  function setSpotJumpOracle(ISpotJumpOracle spotJumpOracle_) external onlyOwner {
    spotJumpOracle = spotJumpOracle_;
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
    _checkInitialMargin(portfolio);
  }

  /////////////////
  // Margin Math //
  /////////////////

  /**
   * @notice revert if a portfolio is under margin
   * @param portfolio Account portfolio
   */
  function _checkInitialMargin(Portfolio memory portfolio) internal view {
    int margin = getInitialMargin(portfolio);
    if (margin < 0) revert PCRM_MarginRequirementNotMet(margin);
  }

  /**
   * @notice Calculate the initial margin of account.
   *         A negative value means the account is X amount over the required margin.
   * @param portfolio Cash + arranged option portfolio.
   * @return margin Amount by which account is over or under the required margin.
   */
  function getInitialMargin(Portfolio memory portfolio) public view returns (int margin) {
    if (portfolio.numStrikesHeld == 0) {
      return portfolio.cash;
    }

    (uint vol, uint spotUp, uint spotDown, uint portfolioDiscount) = getTimeWeightedMarginParams(
      spotShockParams.upInitial,
      spotShockParams.downInitial,
      spotShockParams.timeSlope,
      portfolioDiscountParams.initial,
      portfolio.expiry
    );

    vol = vol.multiplyDecimal(
      _getSpotJumpMultiple(volShockParams.spotJumpMultipleSlope, volShockParams.spotJumpMultipleLookback)
    );

    margin = _calcMargin(portfolio, vol, spotUp, spotDown, portfolioDiscount);

    return margin - portfolioDiscountParams.initialStaticCashOffset.toInt256();
  }

  /**
   * @notice Calculate the maintenance margin of account.
   *         A negative value means the account is X amount over the required margin.
   * @param portfolio Cash + arranged option portfolio.
   * @return margin Amount by which account is over or under the required margin.
   */
  function getMaintenanceMargin(Portfolio memory portfolio) public view returns (int margin) {
    (uint vol, uint spotUp, uint spotDown, uint portfolioDiscount) = getTimeWeightedMarginParams(
      spotShockParams.upMaintenance,
      spotShockParams.downMaintenance,
      spotShockParams.timeSlope,
      portfolioDiscountParams.maintenance,
      portfolio.expiry
    );

    return _calcMargin(portfolio, vol, spotUp, spotDown, portfolioDiscount);
  }

  /**
   * @notice Calculate the initial margin of account, but use rv = 0
   * @param portfolio Cash + arranged option portfolio.
   * @return margin Amount by which account is over or under the required margin.
   */
  function getInitialMarginRVZero(Portfolio memory portfolio) external view returns (int margin) {
    (, uint spotUp, uint spotDown, uint portfolioDiscount) = getTimeWeightedMarginParams(
      spotShockParams.upInitial,
      spotShockParams.downInitial,
      spotShockParams.timeSlope,
      portfolioDiscountParams.initial,
      portfolio.expiry
    );

    // feed vol = 0 into the calculation
    return _calcMargin(portfolio, 0, spotUp, spotDown, portfolioDiscount);
  }

  /**
   * @notice Calculate the initial or maintenance margin of account.
   *         A positive value means the account is X amount over the required margin.
   * @param portfolio Account portfolio.
   * @param vol Shocked vol used in margin calculations
   * @param spotUp Shocked up spot used as inpute in margin scenarios
   * @param spotDown Shocked down spot used as inpute in margin scenarios
   * @param portfolioDiscount Total time based discount applied to the whole portfolio if margin > 0.
   * @return margin Amount by which account is over or under the required margin.
   */
  function _calcMargin(Portfolio memory portfolio, uint vol, uint spotUp, uint spotDown, uint portfolioDiscount)
    internal
    view
    returns (int margin)
  {
    // todo [Anton]: add ability to do RV = 0?

    // If options expired, get settled value.
    if (portfolio.expiry < block.timestamp) {
      return _calcSettledExpiryValue(portfolio) + portfolio.cash;
    }

    // Otherwise, get discounted option value.
    margin = _calcLiveExpiryValue(portfolio, spotUp.toUint128(), spotDown.toUint128(), vol.toUint128());
    if (margin > 0) {
      margin = margin.multiplyDecimal(portfolioDiscount.toInt256());
    }

    // Add cash
    margin += portfolio.cash;
  }

  /**
   * @notice Calculate the settled value of option portfolio.
   * @param portfolio All option portfolio
   * @return expiryValue Value of assets or debt of settled options.
   */
  function _calcSettledExpiryValue(Portfolio memory portfolio) internal view returns (int expiryValue) {
    uint settlementPrice = settlementFeed.getSettlementPrice(portfolio.expiry);
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
      // Solidity forces only static arrays in memory, so need to handle empty positions.
      if (portfolio.strikes[i].calls == 0 && portfolio.strikes[i].puts == 0 && portfolio.strikes[i].forwards == 0) {
        continue;
      }
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
    // todo [Josh]: should probably make separate functions for positive / negative calls
    strikeValue += (strikes.calls >= 0)
      ? strikes.calls.multiplyDecimal(SignedMath.max(markedDownCallValue, 0))
      : strikes.calls.multiplyDecimal(callValue.toInt256());

    // Add put value.
    strikeValue += (strikes.puts >= 0)
      ? strikes.puts.multiplyDecimal(SignedMath.max(markedDownPutValue, 0))
      : strikes.puts.multiplyDecimal(putValue.toInt256());
  }

  //////////////////////////////////////////////
  // Applying Time-Weighting to Margin Params //
  //////////////////////////////////////////////

  /**
   * @notice Applies time weighting to all params used in computing margin.
   *         The param inputs will depend on whether looking for initial or maintenance margin.
   * @param spotUpPercent Percent by which to multiply spot to get the `up` scenario.
   * @param spotDownPercent Percent by which to multiply spot to get the `down` scenario.
   * @param spotTimeSlope Rate at which to increase the shocks with larger `timeToExpiry`.
   * @param portfolioDiscountFactor Initial discounting factor applied when option margin > 0.
   * @param expiry expiry of the portfolio
   * @return vol Volatility.
   * @return spotUp Shocked up spot.
   * @return spotDown Shocked down spot.
   * @return portfolioDiscount Portfolio-wide static discount
   */
  function getTimeWeightedMarginParams(
    uint spotUpPercent,
    uint spotDownPercent,
    uint spotTimeSlope,
    uint portfolioDiscountFactor,
    uint expiry
  ) public view returns (uint vol, uint spotUp, uint spotDown, uint portfolioDiscount) {
    int timeToExpiry = expiry.toInt256() - block.timestamp.toInt256();
    // Can return zero params as settled options do not require these.
    if (timeToExpiry <= 0) {
      return (0, 0, 0, 0);
    }

    vol = _applyTimeWeightToVol(timeToExpiry.toUint256());

    // Get future price as spot, and apply shocks
    uint spot = futureFeed.getFuturePrice(expiry);
    (spotUp, spotDown) =
      _applyTimeWeightToSpotShocks(spot, spotUpPercent, spotDownPercent, spotTimeSlope, timeToExpiry.toUint256());

    // Get portfolio-wide discount
    portfolioDiscount = _applyTimeWeightToPortfolioDiscount(portfolioDiscountFactor, timeToExpiry.toUint256());
  }

  /**
   * @notice Applies time weighting to spot shock params.
   * @param spotUpPercent Percent by which to multiply spot to get the `up` scenario
   * @param spotDownPercent Percent by which to multiply spot to get the `down` scenario
   * @param timeSlope Rate at which to increase the shocks with larger `timeToExpiry`
   * @param timeToExpiry Seconds till option expires.
   * @return up Shocked up spot.
   * @return down Shocked down spot.
   */
  function _applyTimeWeightToSpotShocks(
    uint spot,
    uint spotUpPercent,
    uint spotDownPercent,
    uint timeSlope,
    uint timeToExpiry
  ) internal pure returns (uint up, uint down) {
    uint timeWeight = timeSlope.multiplyDecimal(timeToExpiry * 1e18 / 365 days);

    uint upShock = spotUpPercent + timeWeight;
    uint downShock = (spotDownPercent > timeWeight) ? spotDownPercent - timeWeight : 0;

    return (spot.multiplyDecimal(upShock), spot.multiplyDecimal(downShock));
  }

  /**
   * @notice Applies time weighting to vol used in determining collateral requirement of shorts.
   *         The vol reduces for longer expiries: taken directly from `Avalon/OptionGreekCache.getShockVol()`.
   * @param timeToExpiry Seconds till option expires.
   * @return vol Used to determine collateral requirements for shorts.
   */
  function _applyTimeWeightToVol(uint timeToExpiry) internal view returns (uint vol) {
    VolShockParams memory params = volShockParams;
    if (timeToExpiry <= params.timeA) {
      return params.maxVol;
    }
    if (timeToExpiry >= params.timeB) {
      return params.minVol;
    }

    // Flip a and b so we don't need to convert to int
    return params.maxVol
      - (((params.maxVol - params.minVol) * (timeToExpiry - params.timeA)) / (params.timeB - params.timeA));
  }

  /**
   * @notice Applies time-weighting to the static portfolio discount param.
   * @param staticDiscount Static param determined by whether margin is initial or maintenance.
   * @param timeToExpiry Sec till option expires.
   * @return expiryDiscount Effective discount applied to the positive margin.
   */
  function _applyTimeWeightToPortfolioDiscount(uint staticDiscount, uint timeToExpiry)
    internal
    view
    returns (uint expiryDiscount)
  {
    uint tau = timeToExpiry * 1e18 / 365 days;
    uint exponent = FixedPointMathLib.exp(-SafeCast.toInt256(tau.multiplyDecimal(portfolioDiscountParams.riskFreeRate)));

    // no need for safecast as .setParams() bounds will ensure no overflow
    return staticDiscount.multiplyDecimal(exponent);
  }

  /**
   * @notice In order to account for volatility spikes, uses a spot jump oracle to
   *         find the max % spot jump in the past X seconds.
   *         This max spot jump is then used to scale up the vol shock by `multiple`.
   * @param spotJumpSlope Rate at which vol is added per increase in spot jump.
   * @param lookbackLength The amount of sec the oracle looks back when finding max jump.
   * @return multiple Multiple by which to increase the vol shock.
   */
  function _getSpotJumpMultiple(uint spotJumpSlope, uint32 lookbackLength) internal view returns (uint multiple) {
    uint jumpBasisPoints = uint(spotJumpOracle.getMaxJump(lookbackLength));
    uint jumpPercent = (jumpBasisPoints * DecimalMath.UNIT) / 10000;
    return DecimalMath.UNIT + spotJumpSlope.multiplyDecimal(jumpPercent);
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
        strikeIndex = _addOption(portfolio, currentAsset);

        // if possible, combine calls and puts into forwards
        StrikeGrouping.updateForwards(portfolio.strikes[strikeIndex]);
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

  ////////////
  // Errors //
  ////////////

  error PCRM_OnlyAuction();

  error PCRM_InvalidBidPortion();

  error PCRM_MarginRequirementNotMet(int initMargin);

  error PCRM_InvalidMarginParam();
}
