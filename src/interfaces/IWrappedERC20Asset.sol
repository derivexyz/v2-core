// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20BasedAsset} from "./IERC20BasedAsset.sol";
import {IPositionTracking} from "./IPositionTracking.sol";

interface IWrappedERC20Asset is IERC20BasedAsset, IPositionTracking {
  //////////////
  //  Errors  //
  //////////////
  error WERC_OnlyAccountOwner();
  error WERC_CannotBeNegative();
  error WERC_InvalidSubId();
}
