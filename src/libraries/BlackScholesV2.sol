//SPDX-License-Identifier: ISC
pragma solidity 0.8.13;

// Libraries
import "synthetix/SignedDecimalMath.sol";
import "synthetix/DecimalMath.sol";
import "./FixedPointMathLib.sol";

/**
 * @title BlackScholes
 * @author Lyra
 * @dev Contract to compute the black scholes price of options.
 * The default decimal matches the ethereum standard of 1e18 units of precision.
 */
library BlackScholesV2 {
  using DecimalMath for uint;
  using SignedDecimalMath for int;

  struct PricesDeltaGamma {
    uint callPrice;
    uint putPrice;
    int callDelta;
    int putDelta;
    uint gamma;
    int k;
    uint sqrtTau;
  }

  /**
   * TODO can optimize this by supplying a precomputed sqrtTau into BS
   *  (since oftentimes many of same-expiry options are computed sequesntially)
   * @param timeToExpirySec Number of seconds to the expiry of the option
   * @param volatilityDecimal Implied volatility over the period til expiry as a percentage
   * @param spotDecimal The current price of the base asset
   * @param strikePriceDecimal The strikePrice price of the option
   * @param rateDecimal The percentage risk free rate + carry cost
   */
  struct BlackScholesInputs {
    uint timeToExpirySec;
    uint volatilityDecimal;
    uint spotDecimal;
    uint strikePriceDecimal;
    int rateDecimal;
  }

  uint private constant SECONDS_PER_YEAR = 31536000;
  /// @dev Internally this library uses 18 decimals of precision
  uint private constant UNIT = 1e18;
  uint private constant SQRT_TWOPI = 2506628274631000502;
  /// @dev Below this value, return 0
  int private constant MIN_CDF_STD_DIST_INPUT = (int(UNIT) * -45) / 10; // -4.5
  /// @dev Above this value, return 1
  int private constant MAX_CDF_STD_DIST_INPUT = int(UNIT) * 10;
  /// @dev Value to use to avoid any division by 0 or values near 0
  uint private constant MIN_T_ANNUALISED = UNIT / SECONDS_PER_YEAR; // 1 second
  uint private constant MIN_VOLATILITY = UNIT / 10000; // 0.001%

  /////////////////////////////////////
  // Option Pricing public functions //
  /////////////////////////////////////
  /**
   * @dev Returns call/put prices
   */
  function prices(BlackScholesInputs memory bsInput) public pure returns (uint callPrice, uint putPrice) {
    uint tAnnualised = _annualise(bsInput.timeToExpirySec);
    (int d1, int d2,,) = _d1d2kSqrtTau(
      tAnnualised, bsInput.volatilityDecimal, bsInput.spotDecimal, bsInput.strikePriceDecimal, bsInput.rateDecimal
    );
    (callPrice, putPrice) =
      _optionPrices(tAnnualised, bsInput.spotDecimal, bsInput.strikePriceDecimal, bsInput.rateDecimal, d1, d2);
  }

  /**
   * @dev Returns call/put prices and delta/stdVega for options with given parameters.
   */
  function pricesDeltaGamma(BlackScholesInputs memory bsInput) public pure returns (PricesDeltaGamma memory) {
    uint tAnnualised = _annualise(bsInput.timeToExpirySec);
    (int d1, int d2, int k, uint sqrtTau) = _d1d2kSqrtTau(
      tAnnualised, bsInput.volatilityDecimal, bsInput.spotDecimal, bsInput.strikePriceDecimal, bsInput.rateDecimal
    );
    (uint callPrice, uint putPrice, int callDelta, int putDelta) = _optionPricesDollarDelta(
      tAnnualised, bsInput.spotDecimal, bsInput.strikePriceDecimal, bsInput.rateDecimal, d1, d2
    );
    uint dollarGamma = _dollarGamma(sqrtTau, bsInput.spotDecimal, bsInput.volatilityDecimal, d1);
    return PricesDeltaGamma(callPrice, putPrice, callDelta, putDelta, dollarGamma, k, sqrtTau);
  }

  //////////////////////
  // Computing Greeks //
  //////////////////////

  /**
   * @dev Returns internal coefficients of the Black-Scholes call price formula, d1 and d2.
   * @param tAnnualised Number of years to expiry
   * @param volatility Implied volatility over the period til expiry as a percentage
   * @param spot The current price of the base asset
   * @param strikePrice The strikePrice price of the option
   * @param rate The percentage risk free rate + carry cost
   */
  function _d1d2kSqrtTau(uint tAnnualised, uint volatility, uint spot, uint strikePrice, int rate)
    internal
    pure
    returns (int d1, int d2, int k, uint sqrtTau)
  {
    // Set minimum values for tAnnualised and volatility to not break computation in extreme scenarios
    // These values will result in option prices reflecting only the difference in stock/strikePrice, which is expected.
    // This should be caught before calling this function, however the function shouldn't break if the values are 0.
    tAnnualised = tAnnualised < MIN_T_ANNUALISED ? MIN_T_ANNUALISED : tAnnualised;
    volatility = volatility < MIN_VOLATILITY ? MIN_VOLATILITY : volatility;
    sqrtTau = FixedPointMathLib.sqrt(tAnnualised);
    k = FixedPointMathLib.ln(int(strikePrice.divideDecimal(spot)));
    int vtSqrt = int(volatility.multiplyDecimal(sqrtTau));
    int v2t = (int(volatility.multiplyDecimal(volatility) >> 1) + rate).multiplyDecimal(int(tAnnualised));
    // TODO this down there is a 1000 gas saving - may consider to do some high-lvel
    // checks at the base BS call and compute all internal functions in unchecked mode
    // unchecked {
    //   d1 = (-k + v2t) * 1e18 / (vtSqrt);
    //   d2 = d1 - vtSqrt;
    // }
    d1 = (v2t - k).divideDecimal(vtSqrt);
    d2 = d1 - vtSqrt;
  }

  /**
   * @dev Internal coefficients of the Black-Scholes call price formula.
   * @param tAnnualised Number of years to expiry
   * @param spot The current price of the base asset
   * @param strikePrice The strikePrice price of the option
   * @param rate The percentage risk free rate + carry cost
   * @param d1 Internal coefficient of Black-Scholes
   * @param d2 Internal coefficient of Black-Scholes
   */
  function _optionPrices(uint tAnnualised, uint spot, uint strikePrice, int rate, int d1, int d2)
    internal
    pure
    returns (uint call, uint put)
  {
    uint strikePricePV =
      strikePrice.multiplyDecimal(FixedPointMathLib.exp(int(-rate.multiplyDecimal(int(tAnnualised)))));
    uint spotNd1 = spot.multiplyDecimal(FixedPointMathLib.stdNormalCDF(d1));
    uint strikePriceNd2 = strikePricePV.multiplyDecimal(FixedPointMathLib.stdNormalCDF(d2));

    // We clamp to zero if the minuend is less than the subtrahend
    // In some scenarios it may be better to compute put price instead and derive call from it depending on which way
    // around is more precise.
    call = strikePriceNd2 <= spotNd1 ? spotNd1 - strikePriceNd2 : 0;
    put = call + strikePricePV;
    put = spot <= put ? put - spot : 0;
  }

  /**
   * @dev Internal coefficients of the Black-Scholes call price formula.
   * @param tAnnualised Number of years to expiry
   * @param spot The current price of the base asset
   * @param strikePrice The strikePrice price of the option
   * @param rate The percentage risk free rate + carry cost
   * @param d1 Internal coefficient of Black-Scholes
   * @param d2 Internal coefficient of Black-Scholes
   */
  function _optionPricesDollarDelta(uint tAnnualised, uint spot, uint strikePrice, int rate, int d1, int d2)
    internal
    pure
    returns (uint call, uint put, int callDelta, int putDelta)
  {
    uint strikePricePV =
      strikePrice.multiplyDecimal(FixedPointMathLib.exp(int(-rate.multiplyDecimal(int(tAnnualised)))));
    uint Nd1 = FixedPointMathLib.stdNormalCDF(d1);
    uint spotNd1 = spot.multiplyDecimal(Nd1);
    uint strikePriceNd2 = strikePricePV.multiplyDecimal(FixedPointMathLib.stdNormalCDF(d2));

    // We clamp to zero if the minuend is less than the subtrahend
    // In some scenarios it may be better to compute put price instead and derive call from it depending on which way
    // around is more precise.
    call = strikePriceNd2 <= spotNd1 ? spotNd1 - strikePriceNd2 : 0;
    put = call + strikePricePV;
    put = spot <= put ? put - spot : 0;
    callDelta = int(Nd1).multiplyDecimal(int(spot));
    putDelta = (int(Nd1) - int(UNIT)).multiplyDecimal(int(spot));
  }

  /*
   * Greeks
   */

  /**
   * @dev Returns the option's delta value
   * @param d1 Internal coefficient of Black-Scholes
   */
  function _delta(int d1) internal pure returns (int callDelta, int putDelta) {
    callDelta = int(FixedPointMathLib.stdNormalCDF(d1));
    putDelta = callDelta - int(UNIT);
  }

  function _dollarGamma(uint sqrtTau, uint spot, uint iv, int d1) internal pure returns (uint) {
    return FixedPointMathLib.stdNormal(d1).divideDecimal(sqrtTau.multiplyDecimal(iv)).multiplyDecimal(spot);
  }

  /**
   * @dev Converts an integer number of seconds to a fractional number of years.
   */
  function _annualise(uint secs) internal pure returns (uint yearFraction) {
    return secs.divideDecimal(SECONDS_PER_YEAR);
  }
}
