// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title OptionEncoding
 * @author Lyra
 * @notice Util functions for encoding / decoding IDs into option details.
 *         [ 1 bit ] [ 63 bits ] [ 32 bit ] = uint96 subId
 *           isCall     strike     expiry
 *         Can support:
 *         - expiries: up to year 2106
 *         - strikes: down to 8 decimal points and up to $90B
 */
library OptionEncoding {
  uint constant UINT32_MAX = 4294967295;
  uint constant UINT63_MAX = 9223372036854775807;

  /**
   * @dev Convert option details into subId
   * @param expiry timestamp of expiry
   * @param strike 18 decimal strike price
   * @param isCall if call, then true
   * @return subId ID of option
   */
  function toSubId(uint expiry, uint strike, bool isCall) internal pure returns (uint96 subId) {
    // can support expiry up to year 2106
    if (expiry > UINT32_MAX) {
      revert OE_ExpiryTooLarge(expiry);
    }

    // can support strike granularity down to 8 decimal points
    if (strike % 1e10 > 0) {
      revert OE_StrikeTooGranular(strike);
    }

    // convert to 8 decimal points
    strike = strike / 1e10;

    // can support strike as high as $92,233,720,368
    if (strike > UINT63_MAX) {
      revert OE_StrikeTooLarge(strike);
    }

    uint96 shiftedStrike = uint96(strike) << 32;
    uint96 shiftedIsCall = uint96((isCall) ? 1 : 0) << 95;
    subId = uint96(expiry) | shiftedStrike | shiftedIsCall;
  }

  /**
   * @dev Convert subId into option details
   * @param subId ID of option
   * @return expiry timestamp of expiry
   * @return strike 18 decimal strike price
   * @return isCall if call, then true
   */
  function fromSubId(uint96 subId) internal pure returns (uint expiry, uint strike, bool isCall) {
    expiry = subId & UINT32_MAX;
    strike = ((subId >> 32) & UINT63_MAX) * 1e10;
    isCall = (subId >> 95) > 0;
  }

  ////////////
  // Errors //
  ////////////

  error OE_ExpiryTooLarge(uint expiry);
  error OE_StrikeTooLarge(uint strike);
  error OE_StrikeTooGranular(uint strike);
}
