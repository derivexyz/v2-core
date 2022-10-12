//SPDX-License-Identifier: ISC

pragma solidity ^0.8.13;

/**
 * @title IntLib
 * @author Lyra
 * @notice util functions for Int
 */

library IntLib {
  function abs(int amount) internal pure returns (uint absAmount) {
    return amount >= 0 ? uint(amount) : uint(-amount);
  }
}
