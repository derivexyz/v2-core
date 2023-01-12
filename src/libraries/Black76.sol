//SPDX-License-Identifier: ISC
pragma solidity ^0.8.13;

// Libraries
import "synthetix/SignedDecimalMath.sol";
import "synthetix/DecimalMath.sol";
import "./FixedPointMathLib.sol";

/**
 * @title Black76
 * @author Lyra
 * @notice Contract to compute the black76 price of options.
 */
library Black76 {
  using DecimalMath for uint;
  using SignedDecimalMath for int;
  using FixedPointMathLib for uint;
  using FixedPointMathLib for int;

  struct Black76Inputs {
    // Number of seconds to the expiry of the option
    uint64 timeToExpirySec;
    // Implied volatility over the period til expiry as a percentage
    uint128 volatility;
    // The forward price of the base asset
    uint128 fwdPrice;
    // The strikePrice price of the option
    uint128 strikePrice;
    // The discount factor
    uint64 discount;
  }

  uint private constant SECONDS_PER_YEAR = 365 days;

  /**
   * @dev max sigma * sqrt(tau), above this standard call price converges to 1.0
   *      Proof:
   *      K/F moneyness will enter into a ln() function to calculate d1 and d2
   *      d1 = -m/totalVol + totalVol/2; d2 = -m/totalVol - totalVol/2
   *      max decimal number represnatable by int is (2**255 - 1) / 1e18, min decimal is 1/1e18
   *      at its max, ln(int) = ln((2**255-1) / 1e18) is approx 255 * ln(2) - 18 * ln(10) = 136
   *      at its min, ln(1 / 1e18) = -41
   *      suppose totalVol exeeds MAX_TOTAL_VOL=24.0, then:
   *      if ln(K/F) -> 136, d1 >= 12.0 - 136/24 = 6.33, d2 <= -12.0 - 136/24 = -17.67
   *      i.e. N(d1) -> 1, N(d2) -> 0 (N(d2) would be O(1e-69), m * N(d2) = O(1e-29) = 0)
   *      standard call option price would thus equal 1 (before discounting and scaling by F)
   *      else if ln(m) -> -41.45, d1 >= 12 + 41 / 24 = 13.7, d2 <= 41 / 24 - 12 = -10.3
   *      i.e. N(d1) -> 1, N(d2) -> 0 (m * N(d2) = small number * small number = 0)
   */
  uint private constant MAX_TOTAL_VOL = 24000000000000000000;

  /////////////////////////////////////
  // Option Pricing public functions //
  /////////////////////////////////////

  /**
   * @notice Returns call/put prices for options with given parameters.
   * @param b76Input Input to Black76 pricing.
   * @return callPrice Call price for given Black76 parameters (18-decimal precision).
   * @return putPrice Put price for given Black76 parameters (18-decimal precision).
   */
  function prices(Black76Inputs memory b76Input) public pure returns (uint callPrice, uint putPrice) {
    // todo [Vlad]: fix case where spot == 0 && strike != 0
    
    unchecked {
      uint tAnnualised = _annualise(b76Input.timeToExpirySec);
      // products of <128 bit numbers, cannot overflow here when caseted to 256
      uint totalVol = uint(b76Input.volatility) * uint(FixedPointMathLib.sqrt(tAnnualised)) / 1e18;
      uint fwd = uint(b76Input.fwdPrice);
      uint fwdDiscounted = fwd * uint(b76Input.discount) / 1e18;
      if (b76Input.strikePrice == 0) {
        return (fwdDiscounted, uint(0));
      }
      uint moneyness = uint(b76Input.strikePrice) * 1e18 / fwd;
      (callPrice, putPrice) = _standardPrices(moneyness, totalVol);

      // these below cannot overflow:
      // fwdDiscounted is a product of 128 bit fwd and 64 bit discount over 1e18
      // fwdDiscounted at most takes 128 + 64 - log2(1e18) = 128 + 64 - 59 = 133 bits
      // call standard price is at most 1e18, which has 59 bits, and 133 + 59 < 256
      // put standard price is at most moneyness, which comes from (strike * 1e18 / fwd),
      // putPrice * fwdDiscounted becmoes (strike * 1e18) * (discount / 1e18)
      // putPrice * fwdDiscounted takes up at most (128 + 59 + 64 - 59) < 256 bits
      callPrice = callPrice * fwdDiscounted / 1e18;
      putPrice = putPrice * fwdDiscounted / 1e18;

      // cap the theo prices to resolve any potential rounding errors with super small/big spots/strikes
      callPrice = callPrice > fwdDiscounted ? fwdDiscounted : callPrice;
      uint strikeDiscounted = uint(b76Input.strikePrice) * uint(b76Input.discount) / 1e18;
      putPrice = putPrice > strikeDiscounted ? strikeDiscounted : putPrice;
    }
  }

  ///////////////////////////////////////
  // Option Pricing internal functions //
  ///////////////////////////////////////

  /**
   * @notice Calculates "standard" call price (i.e. with forward = discount = 1)
   * @dev MAX_TOTAL_VOL is checked and 1.0 is returned if it is exceeded (see MAX_TOTAL_VOL)
   *      As for moneyness = (K/F), no checks are needed as long as K and F are proper uint128
   *      Proof:
   *      (K/F) -> this is a result of decimal division (K * 1e18) / F which is at most type(K).max * 1e18
   *      log2((2**128-1) * 1e18) = 188 < 256, provided that strike K is uint128
   *      moneyness is used in the log: no overflow possible since K/F < 2**255-1,
   *      and in multiplying it in (K/F) * N(d2): no overflow possible since
   *      N(d2) is at most 1e18, so the product is at most log2((2**128-1) * 1e18 * 1e18) = 248 bits
   * @param moneyness K/F decimal ratio (strike over forward)
   * @param totalVol sigma * sqrt(time to expiry)
   * @return stdCallPrice Call price, standardized to forward = discount = 1.0
   */
  function _standardCall(uint moneyness, uint totalVol) internal pure returns (uint stdCallPrice) {
    unchecked {
      if (totalVol >= MAX_TOTAL_VOL) return 1e18;
      totalVol = (totalVol == 0) ? 1 : totalVol;
      moneyness = (moneyness == 0) ? 1 : moneyness;
      int k = int(moneyness).ln();
      int halfV2t = int((totalVol >> 1) * totalVol / 1e18);
      int d1 = (halfV2t - k) * 1e18 / int(totalVol);
      int d2 = d1 - int(totalVol);

      uint Nd1 = FixedPointMathLib.stdNormalCDF(d1);
      uint mNd2 = moneyness * FixedPointMathLib.stdNormalCDF(d2) / 1e18;
      return (Nd1 >= mNd2) ? Nd1 - mNd2 : 0;
    }
  }

  /**
   * @notice Calculates "standard" put price (i.e. with forward = discount = 1) from call price & moneyness
   * @param moneyness K/F decimal ratio (strike over forward)
   * @param stdCallPrice Call price, standardized to forward = discount = 1.0
   * @return stdPutPrice Put price, standardized to forward = discount = 1.0
   */
  function _standardPutFromCall(uint moneyness, uint stdCallPrice) internal pure returns (uint stdPutPrice) {
    unchecked {
      uint sum = stdCallPrice + moneyness;
      return (sum >= 1e18) ? sum - 1e18 : 0;
    }
  }

  /**
   * @notice Calculates "standard" call/put prices (i.e. with forward = discount = 1)
   * @param moneyness K/F decimal ratio (strike over forward)
   * @param totalVol sigma * sqrt(time to expiry)
   * @return stdCallPrice Call price, standardized to forward = discount = 1.0
   * @return stdPutPrice Put price, standardized to forward = discount = 1.0
   */
  function _standardPrices(uint moneyness, uint totalVol) internal pure returns (uint stdCallPrice, uint stdPutPrice) {
    unchecked {
      stdCallPrice = _standardCall(moneyness, totalVol);
      stdPutPrice = _standardPutFromCall(moneyness, stdCallPrice);
    }
  }

  /**
   * @notice Converts an integer number of seconds to a fractional number of years.
   * @param secs # of seconds (usually from block.timestamp till option expiry).
   * @return yearFraction An 18-decimal year fraction.
   */
  function _annualise(uint64 secs) internal pure returns (uint yearFraction) {
    unchecked {
      // unchecked saves 500 gas, cannot overflow since input is 64 bit
      return uint(secs) * 1e18 / SECONDS_PER_YEAR;
    }
  }
}
