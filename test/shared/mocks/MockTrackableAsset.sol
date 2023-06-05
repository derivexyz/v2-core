//SPDX-License-Identifier:MIT
pragma solidity ^0.8.18;

import "./MockPositionTracking.sol";
import "./MockGlobalSubIdOITracking.sol";
import "./MockAsset.sol";

contract MockTrackableAsset is MockPositionTracking, MockGlobalSubIdOITracking, MockAsset {
  constructor(IERC20 token_, ISubAccounts account_, bool allowNegativeBalance_)
    MockAsset(token_, account_, allowNegativeBalance_)
  {}
}
