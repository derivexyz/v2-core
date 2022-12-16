// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title OptionEncoding
 * @author Lyra
 * @notice util functions for encoding / decoding IDs into option details
 */

library OptionEncoding {
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
    // check that expiry fits into uint32
    // check that strike fits into uint64
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

}