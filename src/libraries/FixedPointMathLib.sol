// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

library FixedPointMathLib {
  /// @dev Magic numbers for normal CDF
  uint private constant N0 = 4062099735652764000328;
  uint private constant N1 = 4080670594171652639712;
  uint private constant N2 = 2067498006223917203771;
  uint private constant N3 = 625581961353917287603;
  uint private constant N4 = 117578849504046139487;
  uint private constant N5 = 12919787143353136591;
  uint private constant N6 = 650478250178244362;
  uint private constant M0 = 8124199471305528000657;
  uint private constant M1 = 14643514515380871948050;
  uint private constant M2 = 11756730424506726822413;
  uint private constant M3 = 5470644798650576484341;
  uint private constant M4 = 1600821957476871612085;
  uint private constant M5 = 296331772558254578451;
  uint private constant M6 = 32386342837845824709;
  uint private constant M7 = 1630477228166597028;
  uint private constant SQRT_TWOPI_BASE2 = 46239130270042206915;

  /// @dev Computes ln(x) for a 1e27 fixed point. Loses 9 last significant digits of precision.
  function lnPrecise(int x) internal pure returns (int r) {
    return ln(x / 1e9) * 1e9;
  }

  /// @dev Computes e ^ x for a 1e27 fixed point. Loses 9 last significant digits of precision.
  function expPrecise(int x) internal pure returns (uint r) {
    return exp(x / 1e9) * 1e9;
  }

  // Computes ln(x) in 1e18 fixed point.
  // Reverts if x is negative or zero.
  // Consumes 670 gas.
  function ln(int x) internal pure returns (int r) {
    unchecked {
      if (x < 1) {
        if (x < 0) revert LnNegativeUndefined();
        revert Overflow();
      }

      // We want to convert x from 10**18 fixed point to 2**96 fixed point.
      // We do this by multiplying by 2**96 / 10**18.
      // But since ln(x * C) = ln(x) + ln(C), we can simply do nothing here
      // and add ln(2**96 / 10**18) at the end.

      // Reduce range of x to (1, 2) * 2**96
      // ln(2^k * x) = k * ln(2) + ln(x)
      // Note: inlining ilog2 saves 8 gas.
      int k = int(ilog2(uint(x))) - 96;
      x <<= uint(159 - k);
      x = int(uint(x) >> 159);

      // Evaluate using a (8, 8)-term rational approximation
      // p is made monic, we will multiply by a scale factor later
      int p = x + 3273285459638523848632254066296;
      p = ((p * x) >> 96) + 24828157081833163892658089445524;
      p = ((p * x) >> 96) + 43456485725739037958740375743393;
      p = ((p * x) >> 96) - 11111509109440967052023855526967;
      p = ((p * x) >> 96) - 45023709667254063763336534515857;
      p = ((p * x) >> 96) - 14706773417378608786704636184526;
      p = p * x - (795164235651350426258249787498 << 96);
      //emit log_named_int("p", p);
      // We leave p in 2**192 basis so we don't need to scale it back up for the division.
      // q is monic by convention
      int q = x + 5573035233440673466300451813936;
      q = ((q * x) >> 96) + 71694874799317883764090561454958;
      q = ((q * x) >> 96) + 283447036172924575727196451306956;
      q = ((q * x) >> 96) + 401686690394027663651624208769553;
      q = ((q * x) >> 96) + 204048457590392012362485061816622;
      q = ((q * x) >> 96) + 31853899698501571402653359427138;
      q = ((q * x) >> 96) + 909429971244387300277376558375;
      assembly {
        // Div in assembly because solidity adds a zero check despite the `unchecked`.
        // The q polynomial is known not to have zeros in the domain. (All roots are complex)
        // No scaling required because p is already 2**96 too large.
        r := sdiv(p, q)
      }
      // r is in the range (0, 0.125) * 2**96

      // Finalization, we need to
      // * multiply by the scale factor s = 5.549…
      // * add ln(2**96 / 10**18)
      // * add k * ln(2)
      // * multiply by 10**18 / 2**96 = 5**18 >> 78
      // mul s * 5e18 * 2**96, base is now 5**18 * 2**192
      r *= 1677202110996718588342820967067443963516166;
      // add ln(2) * k * 5e18 * 2**192
      r += 16597577552685614221487285958193947469193820559219878177908093499208371 * k;
      // add ln(2**96 / 10**18) * 5e18 * 2**192
      r += 600920179829731861736702779321621459595472258049074101567377883020018308;
      // base conversion: mul 2**18 / 2**192
      r >>= 174;
    }
  }

  // Integer log2
  // @returns floor(log2(x)) if x is nonzero, otherwise 0. This is the same
  //          as the location of the highest set bit.
  // Consumes 232 gas. This could have been an 3 gas EVM opcode though.
  function ilog2(uint x) internal pure returns (uint r) {
    assembly {
      r := shl(7, lt(0xffffffffffffffffffffffffffffffff, x))
      r := or(r, shl(6, lt(0xffffffffffffffff, shr(r, x))))
      r := or(r, shl(5, lt(0xffffffff, shr(r, x))))
      r := or(r, shl(4, lt(0xffff, shr(r, x))))
      r := or(r, shl(3, lt(0xff, shr(r, x))))
      r := or(r, shl(2, lt(0xf, shr(r, x))))
      r := or(r, shl(1, lt(0x3, shr(r, x))))
      r := or(r, lt(0x1, shr(r, x)))
    }
  }

  // Computes e^x in 1e18 fixed point.
  // consumes 500 gas
  function exp(int x) internal pure returns (uint r) {
    unchecked {
      // Input x is in fixed point format, with scale factor 1/1e18.

      // When the result is < 0.5 we return zero. This happens when
      // x <= floor(log(0.5e18) * 1e18) ~ -42e18
      if (x <= -42139678854452767551) {
        return 0;
      }

      // When the result is > (2**255 - 1) / 1e18 we can not represent it
      // as an int256. This happens when x >= floor(log((2**255 -1) / 1e18) * 1e18) ~ 135.
      if (x >= 135305999368893231589) revert ExpOverflow();

      // x is now in the range (-42, 136) * 1e18. Convert to (-42, 136) * 2**96
      // for more intermediate precision and a binary basis. This base conversion
      // is a multiplication by 1e18 / 2**96 = 5**18 / 2**78.
      x = (x << 78) / 5**18;

      // Reduce range of x to (-½ ln 2, ½ ln 2) * 2**96 by factoring out powers of two
      // such that exp(x) = exp(x') * 2**k, where k is an integer.
      // Solving this gives k = round(x / log(2)) and x' = x - k * log(2).
      int k = ((x << 96) / 54916777467707473351141471128 + 2**95) >> 96;
      x = x - k * 54916777467707473351141471128;
      // k is in the range [-61, 195].

      // Evaluate using a (6, 7)-term rational approximation
      // p is made monic, we will multiply by a scale factor later
      int p = x + 2772001395605857295435445496992;
      p = ((p * x) >> 96) + 44335888930127919016834873520032;
      p = ((p * x) >> 96) + 398888492587501845352592340339721;
      p = ((p * x) >> 96) + 1993839819670624470859228494792842;
      p = p * x + (4385272521454847904632057985693276 << 96);
      // We leave p in 2**192 basis so we don't need to scale it back up for the division.
      // Evaluate using using Knuth's scheme from p. 491.
      int z = x + 750530180792738023273180420736;
      z = ((z * x) >> 96) + 32788456221302202726307501949080;
      int w = x - 2218138959503481824038194425854;
      w = ((w * z) >> 96) + 892943633302991980437332862907700;
      int q = z + w - 78174809823045304726920794422040;
      q = ((q * w) >> 96) + 4203224763890128580604056984195872;
      assembly {
        // Div in assembly because solidity adds a zero check despite the `unchecked`.
        // The q polynomial is known not to have zeros in the domain. (All roots are complex)
        // No scaling required because p is already 2**96 too large.
        r := sdiv(p, q)
      }
      // r should be in the range (0.09, 0.25) * 2**96.

      // We now need to multiply r by
      //  * the scale factor s = ~6.031367120...,
      //  * the 2**k factor from the range reduction, and
      //  * the 1e18 / 2**96 factor for base converison.
      // We do all of this at once, with an intermediate result in 2**213 basis
      // so the final right shift is always by a positive amount.
      r = (uint(r) * 3822833074963236453042738258902158003155416615667) >> uint(195 - k);
    }
  }

  /// @notice Calculates the square root of x, rounding down (borrowed from https://ethereum.stackexchange.com/a/97540)
  /// @dev Uses the Babylonian method https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method.
  /// @param x The uint256 number for which to calculate the square root.
  /// @return result The result as an uint256.
  function _sqrt(uint x) internal pure returns (uint result) {
    if (x == 0) {
      return 0;
    }

    // Calculate the square root of the perfect square of a power of two that is the closest to x.
    uint xAux = uint(x);
    result = 1;
    if (xAux >= 0x100000000000000000000000000000000) {
      xAux >>= 128;
      result <<= 64;
    }
    if (xAux >= 0x10000000000000000) {
      xAux >>= 64;
      result <<= 32;
    }
    if (xAux >= 0x100000000) {
      xAux >>= 32;
      result <<= 16;
    }
    if (xAux >= 0x10000) {
      xAux >>= 16;
      result <<= 8;
    }
    if (xAux >= 0x100) {
      xAux >>= 8;
      result <<= 4;
    }
    if (xAux >= 0x10) {
      xAux >>= 4;
      result <<= 2;
    }
    if (xAux >= 0x4) {
      result <<= 1;
    }

    // The operations can never overflow because the result is max 2^127 when it enters this block.
    unchecked {
      result = (result + x / result) >> 1;
      result = (result + x / result) >> 1;
      result = (result + x / result) >> 1;
      result = (result + x / result) >> 1;
      result = (result + x / result) >> 1;
      result = (result + x / result) >> 1;
      result = (result + x / result) >> 1; // Seven iterations should be enough
      uint roundedDownResult = x / result;
      return result >= roundedDownResult ? roundedDownResult : result;
    }
  }

  /**
   * @dev Returns the square root of a value using Newton's method.
   */
  function sqrt(uint x) internal pure returns (uint) {
    // Add in an extra unit factor for the square root to gobble;
    // otherwise, sqrt(x * UNIT) = sqrt(x) * sqrt(UNIT)
    return _sqrt(x * 1e18);
  }

  /**
   * @dev Compute the absolute value of `val`.
   *
   * @param val The number to absolute value.
   */
  function abs(int val) internal pure returns (uint) {
    return uint(val < 0 ? -val : val);
  }

  /**
   * @dev The standard normal distribution of the value.
   */
  function stdNormal(int x) internal pure returns (uint) {
    int y = ((x >> 1) * x) / 1e18;
    return (exp(-y) * 1e18) / 2506628274631000502;
  }

  /**
   * @dev The standard normal cumulative distribution of the value.
   * borrowed from a C++ implementation https://stackoverflow.com/a/23119456
   * original paper: http://www.codeplanet.eu/files/download/accuratecumnorm.pdf
   * consumes 1800 gas
   */
  function stdNormalCDF(int x) public pure returns (uint) {
    unchecked {
      uint z = abs(x);
      uint c;
      if (z > 37 * 1e18) {
        return (x <= 0) ? c : uint(1e18 - int(c));
      } else {
        // z^2 cannot overflow in this "else" block
        uint e = exp(-int(((z >> 1) * z) / 1e18));

        // convert to binary base with factor 1e18 / 2**64 = 5**18 / 2**46.
        // z cant overflow with z < 37 * 1e18 range we're in
        // e cant overflow since its at most 1.0 (at z=0)

        z = (z << 46) / 5**18;
        e = (e << 46) / 5**18;

        if (z < 130438178253327725388) // 7071067811865470000 in decimal (7.07)
        {
          // Hart's algorithm for x \in (-7.07, 7.07)
          uint n;
          uint d;

          n = ((N6 * z) >> 64) + N5;
          n = ((n * z) >> 64) + N4;
          n = ((n * z) >> 64) + N3;
          n = ((n * z) >> 64) + N2;
          n = ((n * z) >> 64) + N1;
          n = ((n * z) >> 64) + N0;

          d = ((M7 * z) >> 64) + M6;
          d = ((d * z) >> 64) + M5;
          d = ((d * z) >> 64) + M4;
          d = ((d * z) >> 64) + M3;
          d = ((d * z) >> 64) + M2;
          d = ((d * z) >> 64) + M1;
          d = ((d * z) >> 64) + M0;

          c = (n * e);
          assembly {
            // Div in assembly because solidity adds a zero check despite the `unchecked`
            // denominator d is a polynomial with non-negative z and, all magic numbers are positive
            // no need to scale since c = (n * e) is already 2^64 times larger
            c := div(c, d)
          }
        } else {
          // continued fracton approximation for abs(x) \in (7.07, 37)
          uint f;
          f = 11990383647911208550; // 13/20 ratio in base 2^64
          // TODO can probaby use assembly here for division
          f = (4 << 128) / (z + f);
          f = (3 << 128) / (z + f);
          f = (2 << 128) / (z + f);
          f = (1 << 128) / (z + f);
          f += z;
          f = (f * SQRT_TWOPI_BASE2) >> 64;
          e = (e << 64);
          assembly {
            // Div in assembly because solidity adds a zero check despite the `unchecked`
            // denominator f is a finite continued fraction that attains min value of 0.4978 at z=37.0
            // so it cannot underflow into 0
            // no need to scale since e is made 2^64 times larger on the line above
            c := div(e, f)
          }
        }
      }

      c = (c * (5**18)) >> 46;
      c = (x <= 0) ? c : uint(1e18 - int(c));
      return c;
    }
  }

  error Overflow();
  error ExpOverflow();
  error LnNegativeUndefined();
}
