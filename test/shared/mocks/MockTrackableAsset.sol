//SPDX-License-Identifier:MIT
pragma solidity ^0.8.18;
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {ISubAccounts} from "../../../src/interfaces/ISubAccounts.sol";

import {MockPositionTracking} from "./MockPositionTracking.sol";
import {MockGlobalSubIdOITracking} from "./MockGlobalSubIdOITracking.sol";
import {MockAsset} from "./MockAsset.sol";


contract MockTrackableAsset is MockPositionTracking, MockGlobalSubIdOITracking, MockAsset {
  constructor(IERC20 token_, ISubAccounts account_, bool allowNegativeBalance_)
    MockAsset(token_, account_, allowNegativeBalance_)
  {}
}
