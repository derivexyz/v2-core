// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "src/interfaces/IChainlinkSpotFeed.sol";
import "src/interfaces/ISpotJumpOracle.sol";

import "openzeppelin/utils/math/SafeCast.sol";
import "lyra-utils/decimals/DecimalMath.sol";
import "lyra-utils/math/IntLib.sol";

contract MockSpotJumpOracle is ISpotJumpOracle {
  uint32 mockMaxJump;

  //////////////
  // External //
  //////////////

  function jumps(uint) external returns (uint32) {}
  function params() external returns (uint32, uint32, uint32, uint32, uint128) {}

  /**
   * @notice Updates the jump buckets if livePrice deviates far enough from the referencePrice.
   * @dev The time gap between the livePrice and referencePrice fluctuates,
   *      but is always < params.secToReferenceStale.
   */
  function updateJumps() public {}

  /**
   * @notice Returns the max jump that is not stale.
   *         If there is no jump that is > params.start, 0 is returned.
   * @return jump The largest jump amount denominated in basis points.
   */
  function getMaxJump(uint32) external view returns (uint32 jump) {
    return mockMaxJump;
  }

  ///////////
  // Mocks //
  ///////////

  /**
   * @notice Updates the jump buckets if livePrice deviates far enough from the referencePrice.
   * @dev The time gap between the livePrice and referencePrice fluctuates,
   *      but is always < params.secToReferenceStale.
   */
  function setMaxJump(uint32 mockMaxJump_) external {
    mockMaxJump = mockMaxJump_;
  }
}
