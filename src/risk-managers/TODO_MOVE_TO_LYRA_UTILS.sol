// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "lyra-utils/math/FixedPointMathLib.sol";
import "openzeppelin/utils/math/SafeCast.sol";

library TODO_MOVE_TO_LYRA_UTILS {
  using SafeCast for uint;

  function min(int a, int b) internal pure returns (int) {
    return (a < b) ? a : b;
  }

  function min(uint a, uint b) internal pure returns (uint) {
    return (a < b) ? a : b;
  }

  function max(uint a, uint b) internal pure returns (uint) {
    return (a > b) ? a : b;
  }

  function decPow(uint a, uint b) internal pure returns (uint) {
    return FixedPointMathLib.exp(FixedPointMathLib.ln(SafeCast.toInt256(a)) * SafeCast.toInt256(b) / 1e18);
  }

  function annualize(uint sec) internal pure returns (uint) {
    return sec * 1e18 / 365 days;
  }
}
