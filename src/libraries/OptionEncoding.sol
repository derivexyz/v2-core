// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/libraries/DecimalMath.sol";

/**
 * @title OptionEncoding
 * @author Lyra
 * @notice util functions for encoding / decoding IDs into option details
 */

library OptionEncoding {
  uint constant UINT32_MAX = 4294967295;
  uint constant UINT64_MAX = 18446744073709551615;

  /**
   * @dev Convert option details into subId
   * @param expiry timestamp of expiry
   * @param strike 18 decimal strike price 
   * @param isCall if call, then true
   * @return subId ID of option
   */
  function toSubId(
    uint expiry, 
    uint strike, 
    bool isCall
  ) internal pure returns (
    uint96 subId
  ) {
    if (expiry > UINT32_MAX) {
      revert OE_ExpiryLargerThanUint32(expiry);
    }
    uint32 castExpiry = uint32(expiry);

    strike= DecimalMath.convertDecimals(strike, 18, 8);
    if (strike > UINT64_MAX) {
      revert OE_StrikeLargerThanUint64(strike);
    }
    uint64 castStrike = uint64(strike);

    // todo: option encoding
  }

  /**
   * @dev Convert subId into option details
   * @param subId ID of option
   * @return expiry timestamp of expiry
   * @return strike 18 decimal strike price 
   * @return isCall if call, then true
   */
  function fromSubId(
    uint96 subId
  ) internal pure returns (
    uint expiry, 
    uint strike, 
    bool isCall
  ) {
    // todo: option decoding
    // cast up into uints
  }

  ////////////
  // Errors //
  ////////////

  error OE_ExpiryLargerThanUint32(uint strike);
  error OE_StrikeLargerThanUint64(uint expiry);

}