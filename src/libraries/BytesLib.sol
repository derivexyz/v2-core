// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/**
 * @title BytesLib
 * @author Lyra
 * @notice bytes to uint conversion
 */
library BytesLib {
  
  /**
   * @dev Convert bytes to uint
   */
  function bytesToUint(bytes memory b) internal pure returns (uint num) {
    for (uint i = 0; i < b.length; i++) {
      num = num + uint(uint8(b[i])) * (2 ** (8 * (b.length - (i + 1))));
    }
  }
}
